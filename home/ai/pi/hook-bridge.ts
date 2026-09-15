import {isToolCallEventType, type ExtensionAPI} from "@earendil-works/pi-coding-agent";
import {execFile} from "node:child_process";
import {homedir} from "node:os";
import {join, resolve as resolvePath} from "node:path";

// Absolute guard paths, colon-separated, injected by the nix wrapper. Each one
// speaks Claude Code's PreToolUse protocol — see ../agent-hooks.
const guards = (process.env.PI_AGENT_HOOKS ?? "").split(":").filter(Boolean);

// A wedged guard would stall every bash call.
const TIMEOUT_MS = 5000;

type HookOutput = {
  hookSpecificOutput?: {
    permissionDecision?: string;
    permissionDecisionReason?: string;
    additionalContext?: string;
  };
};

// Matches pi's own `read` tool resolution (resolveToCwd -> normalizePath's
// expandTilde, on by default): `~`/`~/...` expand to the home dir before
// joining with cwd. Plain path.resolve doesn't expand `~`, which would let a
// `~`-rooted read silently bypass file_path-based guards.
function resolveReadPath(path: string, cwd: string): string {
  const expanded = path === "~" ? homedir() : path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
  return resolvePath(cwd, expanded);
}

function runGuard(bin: string, payload: string): Promise<string> {
  return new Promise((resolve) => {
    const child = execFile(bin, {timeout: TIMEOUT_MS}, (_error, stdout) => resolve(stdout));
    child.stdin?.end(payload);
  });
}

export default function (pi: ExtensionAPI) {
  if (guards.length === 0) return;

  pi.on("tool_call", async (event, ctx) => {
    let payload: string;
    if (isToolCallEventType("bash", event)) {
      payload = JSON.stringify({
        tool_name: "Bash",
        tool_input: {command: event.input.command},
        cwd: ctx.cwd,
      });
    } else if (isToolCallEventType("read", event)) {
      payload = JSON.stringify({
        tool_name: "Read",
        tool_input: {
          file_path: resolveReadPath(event.input.path, ctx.cwd),
          offset: event.input.offset,
          limit: event.input.limit,
        },
        cwd: ctx.cwd,
      });
    } else {
      return;
    }

    for (const bin of guards) {
      let output: HookOutput;
      try {
        output = JSON.parse(await runGuard(bin, payload));
      } catch {
        // Silence is how a guard abstains, and a malformed one must not wedge
        // the turn — both land here.
        continue;
      }

      const decision = output.hookSpecificOutput;
      if (!decision) continue;

      if (decision.permissionDecision === "deny") {
        return {block: true, reason: decision.permissionDecisionReason ?? `Blocked by ${bin}`};
      }

      // "ask" prompts a human when one is attached; with no UI to answer it,
      // mirror Claude Code's auto-deny rather than letting the call through.
      if (decision.permissionDecision === "ask") {
        const reason = decision.permissionDecisionReason ?? `Blocked by ${bin}`;
        const approved = ctx.hasUI ? await ctx.ui.confirm("Confirm", reason) : false;
        if (!approved) return {block: true, reason};
      }

      // pi's tool_call return only controls blocking, so advisory output has no
      // path to the model. Show the user instead of dropping it.
      if (decision.additionalContext && ctx.hasUI) {
        ctx.ui.notify(decision.additionalContext, "warning");
      }
    }
  });
}
