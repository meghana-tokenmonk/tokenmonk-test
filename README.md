# tokenmonk-test

Minimal Cursor workspace used to exercise **project-level agent hooks**.

The tracked runtime surface is [`.cursor/hooks.json`](.cursor/hooks.json) plus the committed probe at [`.cursor/hooks/project-probe.sh`](.cursor/hooks/project-probe.sh). Those hooks are observation-only: they always exit `0` and never block the agent.

## Layout

| Path | Role |
| --- | --- |
| [`.cursor/hooks.json`](.cursor/hooks.json) | Project hook registrations (schema version 1) |
| [`.cursor/hooks/project-probe.sh`](.cursor/hooks/project-probe.sh) | Heartbeat + optional `probe.js` forwarder |
| [`docs/project-hooks.md`](docs/project-hooks.md) | Architecture, event map, setup, and troubleshooting |
| [`spike-results/`](spike-results/) | Recorded cloud-agent firing measurements |
| [`.gitignore`](.gitignore) | Ignores local `.tm-spike/` artifacts |

There is no application code, package manifest, or CI in this repository.

## Intent

Cloud agents load **project** hooks from this repo. They do not load user-level `~/.cursor/hooks.json`. This workspace keeps a small, committed hook surface so TokenMonk can tell whether Cursor invoked the project hooks, even when the optional throwaway plugin cache is missing.

The probe script writes a heartbeat first, then forwards stdin to `probe.js` only if that file exists under:

```text
~/.cursor/plugins/cache/meghud-tokenmonk-throwaway/**/probe.js
```

That cache path is optional. If it is absent, the script still records the invocation and prints a fail-open JSON response.

## Developer setup

1. Clone the repo and open it as a trusted Cursor workspace.
2. Confirm `python3` is on `PATH` (the probe parses `hook_event_name` with it).
3. Optional: install the `meghud-tokenmonk-throwaway` plugin if you need the `probe.js` forwarder. The team `tokenmonk-capture` plugin is a different cache path and is not used here.
4. Run an agent turn that reads a file or runs a shell command.

Then check the heartbeat log:

```bash
cat .tm-spike/project-hook-fired.log
```

Manual smoke test of the same command every project hook runs:

```bash
printf '%s' '{"hook_event_name":"beforeSubmitPrompt","session_id":"local-smoke"}' \
  | .cursor/hooks/project-probe.sh
```

Expected stdout when `probe.js` is missing: `{"continue":true,"permission":"allow"}`. Exit code is always `0`.

## Constraints

- Hooks are command-based only (`type: "command"`). Prompt-based hooks are not configured and do not run in cloud agents.
- Each hook times out after **10 seconds**.
- `failClosed` is unset, so a crash or timeout is fail-open.
- The `stop` hook sets `loop_limit: 1`. The committed probe does not emit `followup_message`.
- Keep `.cursor/hooks.json` valid JSON. A trailing comma prevents Cursor from loading project hooks.

See [`docs/project-hooks.md`](docs/project-hooks.md) for the event list, stdout contract, and common failures.
