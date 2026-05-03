---
name: temporal-split-workers
description: Use when setting up Temporal workers, debugging ActivityNotRegisteredError, or understanding why workflows and activities run on separate queues
---

# Temporal Split-Worker Architecture

## Overview

Split workflows and activities onto separate task queues. API worker hosts lightweight workflow orchestration; standalone worker handles heavy activities.

**Core principle:** Workflows (orchestration) run in the API process. Activities (heavy work) run in dedicated workers with their own resources.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ API Worker (apid)                                               │
│ Task Queue: document-processing                                 │
│ Registers: DocumentProcessingWorkflow                           │
│                                                                 │
│   workflow.ExecuteActivity(ctx, "DownloadAndValidate", input)  │
│                     │                                           │
│                     │ TaskQueue: document-processing-activities │
│                     ▼                                           │
└─────────────────────────────────────────────────────────────────┘
                      │
                      │ Temporal schedules activity
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│ Standalone Worker (document-processor)                          │
│ Task Queue: document-processing-activities                      │
│ Registers: DownloadAndValidateActivity, ProcessAndStoreActivity │
│ Resources: PDF processing, pdfium pool, heavy compute           │
└─────────────────────────────────────────────────────────────────┘
```

## Why Split?

| Concern | Workflows (API) | Activities (Standalone) |
|---------|-----------------|-------------------------|
| CPU | Low (orchestration) | High (PDF processing) |
| Memory | Low | High (pdfium pool) |
| Scaling | Scales with API | Scales independently |
| Failures | Fast retries | Heavy work retried in isolation |
| Deployment | With API | Independent deployment |

## Implementation

### API Worker (Workflow Host)

```go
// api/app/temporal.go
docProcessingTaskQueue := "document-processing"
docProcessingWorker := worker.New(tc.client, docProcessingTaskQueue, worker.Options{})

// Register workflow only
docProcessingWorker.RegisterWorkflow(documentprocessor.DocumentProcessingWorkflow)
```

### Standalone Worker (Activity Host)

```go
// services/proc/workers/document-processor/cmd/worker/main.go
taskQueue := getEnvOrDefault("TEMPORAL_TASK_QUEUE", "document-processing-activities")
temporalWorker := worker.New(temporalClient, taskQueue, worker.Options{})

// Register activities only - NOT workflows
w.worker.RegisterActivity(w.handler.DownloadAndValidateActivity)
w.worker.RegisterActivity(w.handler.ProcessAndStoreActivity)
```

### Workflow Routing Activities to Separate Queue

```go
// api/workers/document-processor/workflows.go
func DocumentProcessingWorkflow(ctx workflow.Context, input Input) (*Result, error) {
    // Route activities to dedicated queue
    activityCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
        TaskQueue:              "document-processing-activities",  // NOT the workflow queue
        StartToCloseTimeout:    30 * time.Minute,
        ScheduleToStartTimeout: 5 * time.Minute,
        RetryPolicy: &temporal.RetryPolicy{
            InitialInterval:    time.Second,
            BackoffCoefficient: 2.0,
            MaximumInterval:    time.Minute,
            MaximumAttempts:    3,
        },
    })

    var result PDFProcessingResult
    err := workflow.ExecuteActivity(activityCtx, "DownloadAndValidateActivity", input).
        Get(activityCtx, &result)
    // ...
}
```

## Debugging

### ActivityNotRegisteredError

**Symptom:** Workflow fails with `activity DownloadAndValidateActivity is not registered`

**Cause:** Activity worker not running or polling wrong queue.

**Fix:**
```bash
# Check what's polling each queue
temporal task-queue describe --task-queue document-processing
temporal task-queue describe --task-queue document-processing-activities

# Verify worker process is running
ps aux | grep document-processor

# Check worker logs
pc logs document-processor

# Verify environment variable
echo $TEMPORAL_TASK_QUEUE  # Should be: document-processing-activities
```

### Workflow Shows Activities But They Don't Execute

**Symptom:** Workflow starts, schedules activities, but activities stay pending.

**Cause:** No worker polling the activities queue.

**Debug:**
```bash
# List workflows
temporal workflow list

# Show specific workflow details
temporal workflow show --workflow-id <workflow-id>

# Check if activities are scheduled to correct queue
# Look for "TaskQueue" in the activity scheduling event
```

### Health Check

Both workers expose gRPC health endpoints:

```bash
# API health (includes workflow worker)
curl -X POST http://localhost:8001/grpc.health.v1.Health/Check \
  -H "Content-Type: application/json" -d '{}'

# Document processor health (activity worker)
curl -X POST http://localhost:8080/grpc.health.v1.Health/Check \
  -H "Content-Type: application/json" -d '{}'
```

## Task Queue Naming Convention

| Pattern | Example | Used For |
|---------|---------|----------|
| `<domain>` | `document-processing` | Workflows |
| `<domain>-activities` | `document-processing-activities` | Activities |
| `api-<purpose>` | `api-notify` | Lightweight API-hosted workflows |

## Adding a New Split Worker

1. **Define task queue constants:**
   ```go
   const (
       WorkflowTaskQueue   = "my-processor"
       ActivitiesTaskQueue = "my-processor-activities"
   )
   ```

2. **Register workflow in API:**
   ```go
   // api/app/temporal.go
   myWorker := worker.New(tc.client, WorkflowTaskQueue, worker.Options{})
   myWorker.RegisterWorkflow(MyWorkflow)
   ```

3. **Route activities in workflow:**
   ```go
   activityCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
       TaskQueue: ActivitiesTaskQueue,
       // ...
   })
   ```

4. **Create standalone worker:**
   ```go
   // services/proc/workers/my-processor/cmd/worker/main.go
   taskQueue := os.Getenv("TEMPORAL_TASK_QUEUE")  // Set to "my-processor-activities"
   w := worker.New(client, taskQueue, worker.Options{})
   w.RegisterActivity(MyActivity)
   ```

5. **Add to process-compose** with correct `TEMPORAL_TASK_QUEUE` env var.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Activity registered on wrong queue | Check `TEMPORAL_TASK_QUEUE` env var |
| Workflow not routing to activities queue | Add `TaskQueue` in `ActivityOptions` |
| Both registered in same worker | Split: workflows in API, activities standalone |
| Missing env var | Set `TEMPORAL_TASK_QUEUE=...-activities` |
