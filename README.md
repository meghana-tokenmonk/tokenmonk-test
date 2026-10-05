# tokenmonk-test

Measurement harness for **Cursor project hooks** on this repository, used for TokenMonk M0 cloud-agent checks.

The repo does not ship an application. It commits a project-hook config, a probe script that always allows the agent to continue, and dated result files from cloud-agent sessions.

## Layout

| Path | Role |
| --- | --- |
| [`.cursor/hooks.json`](.cursor/hooks.json) | Project-hook registry. Every registered event runs the same probe command. |
| [`.cursor/hooks/project-probe.sh`](.cursor/hooks/project-probe.sh) | Heartbeat + optional forwarder to TokenMonk `probe.js`. Always exits `0`. |
| [`spike-results/`](spike-results/) | Committed session reports. Do not confuse these with the live log. |
| `.tm-spike/` | Runtime heartbeat directory. Gitignored. Recreated on each hook fire. |

## Quick start

1. Confirm `.cursor/hooks.json` is valid JSON (a trailing comma prevents Cursor from loading hooks).
2. Start a **new** Cursor cloud agent or local Agent session from a revision that already has valid `hooks.json`.
3. Exercise tools (Read, Shell, Write).
4. Inspect the live heartbeat:

```bash
wc -l .tm-spike/project-hook-fired.log
awk '{for (i=1;i<=NF;i++) if ($i ~ /^event=/) print $i}' .tm-spike/project-hook-fired.log | sort | uniq -c
```

5. Record a new file under `spike-results/` only when the session answers a measurement question.

Manual self-test of the script (not a Cursor invocation):

```bash
printf '%s' '{"hook_event_name":"manualSelfTest","session_id":"manual-self-test"}' \
  | .cursor/hooks/project-probe.sh
# stdout: {"continue":true,"permission":"allow"}
```

See [docs/project-hooks.md](docs/project-hooks.md) for architecture, registered events, how to interpret results, and pitfalls.
