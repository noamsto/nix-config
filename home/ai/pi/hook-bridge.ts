import {isToolCallEventType, type ExtensionAPI} from "@earendil-works/pi-coding-agent";
import {execFile} from "node:child_process";

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

function runGuard(bin: string, payload: string): Promise<string> {
  return new Promise((resolve) => {
    const child = execFile(bin, {timeout: TIMEOUT_MS}, (_error, stdout) => resolve(stdout));
    child.stdin?.end(payload);
  });
}

export default function (pi: ExtensionAPI) {
  if (guards.length === 0) return;

  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;

    const payload = JSON.stringify({
      tool_name: "Bash",
      tool_input: {command: event.input.command},
      cwd: ctx.cwd,
    });

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

      // pi's tool_call return only controls blocking, so advisory output has no
      // path to the model. Show the user instead of dropping it.
      if (decision.additionalContext && ctx.ui.hasUI) {
        ctx.ui.notify(decision.additionalContext, "warning");
      }
    }
  });
}
