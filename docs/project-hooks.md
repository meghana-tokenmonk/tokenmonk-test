# Project hooks

How [`.cursor/hooks.json`](../.cursor/hooks.json) is wired, what it covers, and how to operate it.

## Architecture

```text
Cursor agent event
        │
        ▼
.cursor/hooks.json  (project hooks, schema version 1)
        │  timeout: 10s, type: command
        ▼
.cursor/hooks/project-probe.sh
        │
        ├── append  → $TM_SPIKE_DIR/project-hook-fired.log
        │             (default: <repo>/.tm-spike/)
        │
        └── if probe.js exists under
            ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway
              stdin → node probe.js --strategy=project-hook --source=project
            else
              stdout → {"continue":true,"permission":"allow"}
```

Cursor loads `.cursor/hooks.json` from the repo root. Cloud agents use these project hooks; they do **not** load `~/.cursor/hooks.json`.

The committed shell script exists so a missing plugin cache cannot be confused with Cursor not invoking the hook. The heartbeat is written before any `probe.js` lookup.

## Registered events

All ten entries run the same command. Every event below is supported on cloud agents ([Cursor hooks](https://cursor.com/docs/hooks)).

| Event | When it fires |
| --- | --- |
| `beforeSubmitPrompt` | After send, before the backend request |
| `preToolUse` | Before any tool runs |
| `postToolUse` | After a tool succeeds |
| `beforeShellExecution` | Before a shell command runs |
| `afterShellExecution` | After a shell command finishes |
| `beforeReadFile` | Before a file read |
| `afterFileEdit` | After a write/edit tool changes a file |
| `afterAgentThought` | After a thinking block completes |
| `afterAgentResponse` | After the assistant message completes |
| `stop` | Agent loop ends (`loop_limit: 1`) |

Events that are **not** registered here: `sessionStart`, `sessionEnd`, `postToolUseFailure`, `beforeMCPExecution`, `afterMCPExecution`, `subagentStart`, `subagentStop`, `preCompact`, plus Tab and `workspaceOpen` hooks.

`sessionStart`, `sessionEnd`, and MCP execution hooks also do not run in cloud agents.

## Command contract

Each hook is:

```json
{
  "type": "command",
  "timeout": 10,
  "command": ".cursor/hooks/project-probe.sh"
}
```

`stop` also sets `"loop_limit": 1`.

Verified behavior of [`project-probe.sh`](../.cursor/hooks/project-probe.sh):

- Reads hook JSON from stdin, then always exits `0`.
- Resolves the spike directory as `TM_SPIKE_DIR`, else `$CURSOR_PROJECT_DIR/.tm-spike`, else `$PWD/.tm-spike`.
- Appends one heartbeat line:

  ```text
  <ISO-8601-UTC> event=<hook_event_name|unknown> cwd=<pwd> home=<HOME> cursor_project_dir=<CURSOR_PROJECT_DIR> stdin_bytes=<n>
  ```

- Looks up the first `probe.js` under `~/.cursor/plugins/cache/meghud-tokenmonk-throwaway`.
- If that file is present, forwards the original stdin to:

  ```bash
  node <probe.js> --strategy=project-hook --source=project
  ```

- If `probe.js` is missing, or that `node` invocation fails, prints `{"continue":true,"permission":"allow"}`.
- Does not return `deny`, `continue: false`, or `followup_message`.

`.tm-spike/` is gitignored. Treat the log as local telemetry: the heartbeat stores event name and byte counts, not payload text, but stdin still flows through the process.

## Local verification

```bash
test -x .cursor/hooks/project-probe.sh || chmod +x .cursor/hooks/project-probe.sh

printf '%s' '{"hook_event_name":"preToolUse","session_id":"local-smoke"}' \
  | .cursor/hooks/project-probe.sh
```

| Check | Expected |
| --- | --- |
| stdout (no `probe.js`) | `{"continue":true,"permission":"allow"}` |
| exit code | `0` |
| heartbeat | Last line of `.tm-spike/project-hook-fired.log` has `event=preToolUse` |

To confirm Cursor (not just the smoke test) is invoking hooks, run an agent turn that reads a file or executes a shell command, then re-read the heartbeat log. New lines for `beforeReadFile` / `beforeShellExecution` mean the project hooks loaded.

## Cloud-agent notes

- Cloud agents run **command-based project hooks** only. User-level `~/.cursor/hooks.json` is not available.
- Hooks do not run during early read-only exploratory turns. They start once the environment is writable ([Cursor hooks](https://cursor.com/docs/hooks)).
- Cursor loads `hooks.json` at session start. Repairing invalid JSON later in the **same** session does not produce invocations. Start a new agent from a revision that already has valid JSON.
- A required team plugin with `enabledCapabilities: ["static"]` is not a project-hook substitute. Project heartbeats can increment while the team plugin leaves no hook artifacts.

### Recorded measurements

| Session | Boot `hooks.json` | Project hooks fired? | Notes |
| --- | --- | --- | --- |
| [`bc-abc4fe2f`](../spike-results/cloud-agent-bc-abc4fe2f-project-hooks.json) | Invalid JSON in the snapshot (`51eec9c`) | No | Fast-forwarding to valid JSON mid-session did not recover hooks. |
| [`bc-64a8fb5c`](../spike-results/cloud-agent-bc-64a8fb5c-project-hooks.json) | Valid JSON at `65ad7bc` | Yes | Writable session; heartbeat log present. Throwaway `probe.js` cache absent, so the script fail-opened. |

Observed Cursor-invoked events in `bc-64a8fb5c` (docs turn, still in progress): `preToolUse`, `postToolUse`, `beforeReadFile`, `beforeShellExecution`, `afterShellExecution`, `afterFileEdit`.

Not observed in that same turn: `beforeSubmitPrompt` (the kickoff prompt can be submitted before hooks load), `afterAgentThought`, `afterAgentResponse`, `stop` (session still running when counted). Missing those names is not proof the registrations failed.

## Troubleshooting

| Symptom | Likely cause | What to check |
| --- | --- | --- |
| No heartbeat after an agent turn | Hooks did not load, or the turn was still read-only | Confirm `.cursor/hooks.json` is valid JSON **at session start**; run the smoke test above |
| Heartbeat present, but no `probe.js` side effects | Throwaway plugin cache missing | `ls ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway`. The team `meghud-tokenmonk-cursor-plugin` cache is a different path and is not consulted |
| Team plugin installed, but no plugin hook files | Cloud plugin capability is `static` only | Project heartbeats can still increment. Do not use plugin logs as the project-hook signal |
| `hooks.json` looks right but nothing fires | Invalid JSON (trailing comma historically broke `afterAgentResponse`) | `python3 -m json.tool .cursor/hooks.json` |
| Hook times out at 10s | `python3` or `node` blocked | Run the smoke test; `command -v python3`; if forwarding, `command -v node` |
| Events from the wrong plugin build | Multiple throwaway cache dirs; `find \| head -1` picks the first path | List matching `probe.js` files and compare the chosen path |
| Hook ran but the agent still proceeded after a crash | `failClosed` is unset (fail-open) | Expected. This fixture must not block the agent. |
| `stop` appears to re-enter the loop | Follow-up from another hook source | This file caps `loop_limit` at `1` and the committed probe does not emit `followup_message` |

## Constraints

- Keep this fixture observation-only. Adding `failClosed: true`, `deny`, or `followup_message` would change the M0 spike contract.
- Do not put credentials in `command`, `args`, or `env` blocks.
- Prefer editing the existing `hooks.json` and `project-probe.sh` over adding a second project hook file.
- User-level hooks cannot replace this file for cloud coverage.
- Keep `hooks.json` strict JSON. Cursor will not load project hooks from a file that fails to parse.
