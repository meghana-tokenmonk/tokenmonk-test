# tokenmonk-test

Minimal Cursor workspace used to exercise **project-level agent hooks**.

The only tracked runtime config is [`.cursor/hooks.json`](.cursor/hooks.json). Those hooks invoke the TokenMonk throwaway probe (`probe.js`) when that plugin is installed locally, and they never block the agent.

## Layout

| Path | Role |
| --- | --- |
| [`.cursor/hooks.json`](.cursor/hooks.json) | Project hook registrations (schema version 1) |
| [`docs/project-hooks.md`](docs/project-hooks.md) | Architecture, event map, setup, and troubleshooting |

There is no application code, package manifest, or CI in this repository.

## Intent

Project hooks are the configuration that **cloud agents and teammates actually run**. User-level `~/.cursor/hooks.json` does not load in cloud VMs. This repo keeps a small, committed hook surface so TokenMonk can measure whether project hooks fire and how they resolve the installed plugin.

The probe script is **not** vendored here. Hooks locate it at:

```text
~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/<id>/<id>/probe.js
```

## Developer setup

1. Clone the repo and open it as a trusted Cursor workspace.
2. Install the `meghud-tokenmonk-throwaway` plugin so the cache path above exists.
3. Confirm `node` is on `PATH` (hooks spawn `node …/probe.js`).
4. Run an agent turn. Hook events should append scrubbed records to `~/.tokenmonk-spike/cursor-events.jsonl`.

Manual smoke test of the same command the project hooks use:

```bash
PLUGIN_DIR="$(ls -d ~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/*/*/ 2>/dev/null | head -1)"
printf '%s\n' '{"hook_event_name":"beforeSubmitPrompt","session_id":"local-smoke"}' \
  | node "${PLUGIN_DIR}probe.js" --strategy=project-hook --source=project
```

Expected stdout: `{"continue":true}`. Exit code is always `0` when the script runs.

## Constraints

- Hooks are command-based only (`type: "command"`). Prompt-based hooks are not configured and do not run in cloud agents.
- Each hook times out after **5 seconds**.
- `failClosed` is unset, so a crash or timeout is fail-open.
- The `stop` hook sets `loop_limit: 1` and the probe never emits `followup_message`.

See [`docs/project-hooks.md`](docs/project-hooks.md) for the event list, stdout contract, and common failures.
