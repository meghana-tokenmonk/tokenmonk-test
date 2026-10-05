# Project hooks

How this repo observes Cursor project hooks, how to tell a real invocation from a self-test, and how to record a session.

Official Cursor hook schema and cloud-agent support: [cursor.com/docs/hooks](https://cursor.com/docs/hooks). This page documents **this repository's** config and probe only.

## Intent

TokenMonk M0 needs a yes/no signal: did Cursor invoke `.cursor/hooks.json` in this session?

Early probes called `probe.js` from the plugin cache with an inline `find`/`node` command. That could not distinguish three failures:

1. Cursor never loaded or invoked project hooks.
2. The command never started (`node` / `find` failed).
3. `probe.js` was missing from the plugin cache.

`.cursor/hooks/project-probe.sh` splits those cases. It always writes a heartbeat that does not depend on the plugin cache, then forwards stdin to `probe.js` when that file exists.

## Architecture

```
Cursor agent loop
        │  stdin JSON (includes hook_event_name)
        ▼
.cursor/hooks.json          version 1, type=command, timeout=10s
        │  command: .cursor/hooks/project-probe.sh
        ▼
project-probe.sh            always exit 0
        │
        ├─ append .tm-spike/project-hook-fired.log
        └─ if ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/**/probe.js exists
              pipe stdin → node probe.js --strategy=project-hook --source=project
           else
              print {"continue":true,"permission":"allow"}
```

The script is fail-open on purpose:

- `set -u` only; missing files and failed subprocesses are ignored.
- Heartbeat write failures are swallowed.
- If `probe.js` is missing or `node` fails, stdout is still `{"continue":true,"permission":"allow"}`.
- Final `exit 0` so a probe bug does not block the agent.

### Environment

| Variable | Used for |
| --- | --- |
| `CURSOR_PROJECT_DIR` | Repo root when Cursor sets it; otherwise `$PWD`, then `/workspace`. |
| `TM_SPIKE_DIR` | Heartbeat directory. Defaults to `$ROOT/.tm-spike`. Exported before `probe.js` so the plugin probe can write to the same place. |
| `HOME` | Plugin-cache search root (`$HOME/.cursor/plugins/cache/meghud-tokenmonk-throwaway`). |

`.gitignore` ignores `.tm-spike/` and `.tm-spike-trigger.txt`. Live logs stay on the VM; only files under `spike-results/` are committed.

## Registered events

All entries are `type: command`, `timeout: 10`, command `.cursor/hooks/project-probe.sh`.

| Event | Notes in this repo |
| --- | --- |
| `beforeSubmitPrompt` | Should fire on the user turn if hooks loaded before tools run. |
| `preToolUse` / `postToolUse` | Generic tool wrappers. Observed on cloud agents when hooks loaded. |
| `beforeShellExecution` / `afterShellExecution` | Shell tool only. |
| `beforeReadFile` | Read / file-access tools. |
| `afterFileEdit` | Write / edit tools. |
| `afterAgentThought` | Fires during the turn if registered and loaded. |
| `afterAgentResponse` | End of agent message. |
| `stop` | Same command, plus `"loop_limit": 1` so a stop follow-up cannot loop. |

Cursor's cloud-agent docs also list `postToolUseFailure`, `subagentStart`, `subagentStop`, and `preCompact`. This repo does not register those.

Cloud agents load project hooks from `.cursor/hooks.json`. They do not load `~/.cursor/hooks.json`. Hooks do not run during early read-only cloud turns; they start once the workspace is writable.

## Probe contract

### Input

Cursor sends one JSON object on stdin. The probe reads `hook_event_name` (string). Missing or invalid JSON becomes `event=unknown`.

### Heartbeat line

Appended to `$TM_SPIKE_DIR/project-hook-fired.log`:

```
2026-10-05T16:02:11Z event=beforeShellExecution cwd=/workspace home=/home/ubuntu cursor_project_dir=/workspace stdin_bytes=753
```

Fields: UTC timestamp, event name, process cwd, `$HOME`, `$CURSOR_PROJECT_DIR`, stdin byte count. The raw payload is not stored.

### Output

When `probe.js` is absent (typical on a cloud VM that only has unrelated plugins), the script prints:

```json
{"continue":true,"permission":"allow"}
```

That is an allow response for permission-style hooks. Combined with `exit 0`, the probe never denies a tool.

### Manual vs Cursor-invoked

Running the script yourself writes a heartbeat. That is **not** evidence that Cursor loaded hooks.

Treat a record as Cursor-invoked only when:

- you did not pipe stdin into `project-probe.sh` or `probe.js` yourself, and
- `session_id` is not a self-test value such as `manual-self-test`.

## How to measure a session

1. **Boot from valid JSON.** Cursor loads `.cursor/hooks.json` at session start. Repairing the file later in the same session has not produced invocations in recorded runs. Validate before starting:

   ```bash
   python3 -c 'import json,sys; json.load(open(".cursor/hooks.json")); print("ok")'
   ```

2. **Exercise several event classes.** At least one Read, one Shell, and one Write. That covers `beforeReadFile`, `preToolUse`/`postToolUse`, `beforeShellExecution`/`afterShellExecution`, and `afterFileEdit`.

3. **Read the heartbeat, not plugin paths.**

   ```bash
   test -f .tm-spike/project-hook-fired.log && echo "hooks fired" || echo "no heartbeat"
   awk '{for (i=1;i<=NF;i++) if ($i ~ /^event=/) print $i}' .tm-spike/project-hook-fired.log | sort | uniq -c
   ```

4. **Optional:** if `probe.js` is on the VM, also check `$TM_SPIKE_DIR/cursor-events.jsonl`. Absence of that file with a present heartbeat means hooks fired and the plugin probe was not installed.

5. **Commit a report** under `spike-results/` when the run answers a measurement question. Use the existing filename pattern `cloud-agent-<bcId>-<topic>.json`.

### Report shape

[`spike-results/cloud-agent-bc-abc4fe2f-project-hooks.json`](../spike-results/cloud-agent-bc-abc4fe2f-project-hooks.json) is the template:

- `run`: `bcId`, URL, surface, repo, `testedAt`
- `question` / `answer`
- `evidence`: Cursor-invoked counts, whether the heartbeat existed, whether a manual probe worked
- `triggersAttempted`: events you expected
- `confounders`: snapshot SHA, invalid JSON, missing plugin cache
- `conclusion`

## Recorded results

| Session | `hooks.json` at boot | Heartbeat | Notes |
| --- | --- | --- | --- |
| `bc-abc4fe2f` (2026-09-06) | Stale snapshot at `51eec9c` (invalid JSON: trailing comma after `afterAgentResponse`) | No | Probe worked when run by hand. Fast-forwarding to valid `main` in the same session did not start invocations. |
| `bc-a9bc921c` (2026-09-07, team-plugin PR) | Valid project `hooks.json` | Yes (119 lines: `preToolUse`, `postToolUse`, `beforeShellExecution`, `afterFileEdit`) | Control for team *plugin* hooks, which did not fire. |
| `bc-0009f279` (2026-10-05, this docs run) | Valid `hooks.json` on `main` (`65ad7bc`) | Yes | Observed `preToolUse`, `postToolUse`, `beforeReadFile`, `beforeShellExecution`, `afterShellExecution` during ordinary tool use. Plugin cache had no `meghud-tokenmonk-throwaway` / `probe.js`. |

## Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| No `.tm-spike/project-hook-fired.log` | Hooks not loaded, or still in a read-only cloud turn | Confirm `hooks.json` parses. Start a **new** agent from that revision. Perform a write or shell command after the workspace is writable. |
| Heartbeat exists, no `cursor-events.jsonl` | Expected when `probe.js` is missing | Heartbeat is sufficient for "did project hooks fire?" |
| Heartbeat only from `event=manualSelfTest` or `session_id=manual-self-test` | You ran the script | Not a Cursor invocation. |
| `hooks.json` edited this session, still no log | Config is loaded at session start | Do not reuse the session. Open a new cloud agent. |
| Invalid JSON / trailing comma | Cursor will not load the file | `python3 -c 'import json; json.load(open(".cursor/hooks.json"))'` before merge. |
| Inline `node "$(find ...)/probe.js"` in `hooks.json` | Pre-`60ca0c7` design | Keep the committed `project-probe.sh` path so a missing plugin cannot hide a missed invocation. |
| Team/plugin hooks silent while project hooks fire | Different load path | Project hooks are this repo. Plugin hooks come from the marketplace artifact and `enabledCapabilities`. Do not treat one as a proxy for the other. |

## Constraints

- Do not add blocking policy to `project-probe.sh`. It is a measurement probe, not a security gate (`failClosed` is unset; default is fail-open).
- Keep `"version": 1` and strict JSON (no comments, no trailing commas).
- Keep `stop.loop_limit` at `1` unless you intend stop follow-ups.
- Do not commit `.tm-spike/`. Commit only interpreted results under `spike-results/`.
- Command paths are relative to the project root (`.cursor/hooks/project-probe.sh`), matching Cursor's project-hook rule.
