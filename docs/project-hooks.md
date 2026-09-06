# Project hooks

How [`.cursor/hooks.json`](../.cursor/hooks.json) is wired, what it covers, and how to operate it.

## Architecture

```text
Cursor agent event
        │
        ▼
.cursor/hooks.json  (project hooks, schema version 1)
        │  timeout: 5s, type: command
        ▼
node "$(ls -d ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/*/*/ | head -1)probe.js"
        │  --strategy=project-hook --source=project
        ├── stdout → JSON Cursor parses (allow / continue)
        ├── stderr → human-readable probe line
        └── append  → ~/.tokenmonk-spike/cursor-events.jsonl
```

Cursor loads this file from the repo root. Cloud agents use these project hooks; they do **not** load `~/.cursor/hooks.json`.

The glob + `head -1` exists because project hook `command` strings do not receive `${CURSOR_PLUGIN_ROOT}` the way plugin-owned hooks do. The first matching cache directory wins (lexicographic `ls` order, not install time).

## Registered events

All seven entries run the same command. Every event below is supported on cloud agents.

| Event | When it fires | Probe stdout |
| --- | --- | --- |
| `beforeSubmitPrompt` | User/agent prompt is about to be sent | `{"continue":true}` |
| `preToolUse` | Before any tool runs | `{"permission":"allow"}` |
| `postToolUse` | After a tool succeeds | `{}` |
| `beforeShellExecution` | Before a shell command runs | `{"permission":"allow"}` |
| `afterFileEdit` | After a write/edit tool changes a file | `{}` |
| `afterAgentThought` | After a thinking block completes | `{}` |
| `stop` | Agent loop ends (`loop_limit: 1`) | `{}` |

Events that are **not** registered here (even though the throwaway plugin may register them): `sessionStart`, `sessionEnd`, `afterShellExecution`, `postToolUseFailure`, `beforeReadFile`, `beforeMCPExecution`, `afterMCPExecution`, `subagentStart`, `subagentStop`, `preCompact`, `afterAgentResponse`, `workspaceOpen`.

## Command contract

Each hook is:

```json
{
  "type": "command",
  "timeout": 5,
  "command": "node \"$(ls -d ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/*/*/ 2>/dev/null | head -1)probe.js\" --strategy=project-hook --source=project"
}
```

`stop` also sets `"loop_limit": 1`.

Flags the probe records on each event:

| Flag | Value in this repo | Meaning |
| --- | --- | --- |
| `--strategy` | `project-hook` | Distinguishes these entries from plugin-owned hooks (`repo-plugin-root`) |
| `--source` | `project` | Distinguishes this registration site from `plugin` / `repo` |

Verified probe behavior (from the installed `probe.js`, not vendored in this repo):

- Always prints the JSON response **before** logging, then exits `0`.
- Never returns `deny`, `continue: false`, or `followup_message`.
- Scrubs prompt text, file contents, shell commands, and emails before writing the JSONL log.
- Swallows filesystem and parse errors so a probe failure cannot block the agent.

## Local verification

```bash
PLUGIN_DIR="$(ls -d ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/*/*/ 2>/dev/null | head -1)"
test -f "${PLUGIN_DIR}probe.js" || { echo "plugin cache missing"; exit 1; }

printf '%s\n' '{"hook_event_name":"preToolUse","session_id":"local-smoke"}' \
  | node "${PLUGIN_DIR}probe.js" --strategy=project-hook --source=project
```

| Check | Expected |
| --- | --- |
| stdout | `{"permission":"allow"}` for `preToolUse` / `beforeShellExecution`; `{"continue":true}` for `beforeSubmitPrompt` |
| exit code | `0` |
| JSONL | Last line of `~/.tokenmonk-spike/cursor-events.jsonl` has `"strategy":"project-hook"` and `"hook_source":"project"` |

Do not inspect that JSONL for secrets. The probe redacts token-shaped values, but treat the file as local telemetry.

## Troubleshooting

| Symptom | Likely cause | What to check |
| --- | --- | --- |
| No JSONL lines after an agent turn | Plugin cache missing or `node` not on `PATH` | `ls ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway` and `command -v node` |
| Hook times out at 5s | `probe.js` not found; `node` waits on a bad path or stdin | Run the smoke test above; confirm the glob expands to a directory that contains `probe.js` |
| Events from the wrong plugin build | Multiple cache dirs; `ls \| head -1` picks the first name | List the cache directories and compare the chosen path |
| Hook ran but agent still proceeded after a crash | `failClosed` is unset (fail-open) | Expected. This fixture must not block the agent. |
| `stop` appears to re-enter the loop | Follow-up from another hook source | This file caps `loop_limit` at `1` and the probe does not emit `followup_message` |
| Cloud run never fires hooks on the first turns | Cloud agents can start read-only | Hooks start after the environment is writable ([Cursor hooks](https://cursor.com/docs/hooks)) |

## Constraints

- Keep this file observation-only. Adding `failClosed: true`, `deny`, or `followup_message` would change the M0 spike contract.
- Do not put credentials in `command`, `args`, or `env` blocks. The probe records substitution metadata and env **names**.
- Prefer editing this existing `hooks.json` over adding a second project hook file.
- User-level hooks cannot replace this file for cloud coverage.
