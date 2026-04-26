# docker-claude

Run Claude Code in a hardened (as possible), firewalled container with
per-project isolated credentials. Drop this directory into any repo,
write a short config, run one script.

This toolset and system-prompt could potentially be used with any LLM
coding tool, and at that point it would make sense to rename it.

**WARNING: Only use this if you know what it all does and accept any risks.**

## What you get

- **Network allow-list.** Outbound traffic is restricted to
  `api.anthropic.com` plus whatever domains you list in the config.
  Everything else is dropped at the iptables level — if Claude or any
  subprocess is tricked into phoning home, it can't.
- **Capability drop.** The container starts with `--cap-drop=ALL`,
  re-adds only `NET_ADMIN` for the firewall init, then drops to an
  unprivileged `dev` user; the uid change clears kernel caps, so
  nothing Claude launches can re-open iptables.
- **`no-new-privileges`.** setuid / fscaps can't elevate.
- **Resource caps.** `--pids-limit` and `--memory` prevent fork bombs
  and runaway memory.
- **Isolated credentials.** Instead of mounting your host `~/.claude`,
  each project keeps its own login in `.docker-claude/` (gitignored).
  You log in once per project; it persists across runs. One project's
  compromise doesn't leak Claude sessions elsewhere.
- **Reusable across projects.** Everything project-specific lives in
  one file (`docker-claude.config`). No editing of the Dockerfile or
  launcher is needed for normal use.

## Setup

1. Copy this `docker-claude/` directory into your project's root.
2. Copy `docker-claude/config.example` to `<project-root>/docker-claude.config`
   and edit:
   - `BASE_IMAGE` — toolchain the project needs (e.g.
     `rust:1.94-slim-bookworm`, `python:3.12-slim`, `node:22-slim`).
   - `ALLOWED_DOMAINS` — add your package registry (`pypi.org`,
     `registry.npmjs.org`, `crates.io`, ...).
   - `IMAGE_NAME` — any unique-per-project string.
   - `CLAUDE_PROMPT` — optional default prompt.
3. Add `.docker-claude/` to your `.gitignore`.
4. Run: `./docker-claude/run.sh`
   - First run: Claude will prompt you to log in. Creds save to
     `.docker-claude/` and are reused on subsequent runs.
   - `--rebuild` forces both base and Claude images to rebuild.
   - Positional arg sets the prompt: `./docker-claude/run.sh "fix the failing test"`.

## Config reference

All variables with their defaults are documented at the top of
`docker-claude/run.sh`. Quick list:

| Variable                | Default                            | Purpose                                                        |
|-------------------------|------------------------------------|----------------------------------------------------------------|
| `BASE_IMAGE`            | `debian:bookworm-slim`             | Image Claude layers on. Must have your project toolchain.      |
| `BASE_IMAGE_CONTEXT`    | *(empty)*                          | If set, run.sh `docker build`s BASE_IMAGE from this path first.|
| `BASE_IMAGE_DOCKERFILE` | `Dockerfile`                       | Dockerfile path relative to BASE_IMAGE_CONTEXT.                |
| `IMAGE_NAME`            | `docker-claude-$(basename repo)`   | Name of the Claude image.                                      |
| `ALLOWED_DOMAINS`       | `api.anthropic.com sentry.io`      | Space-separated outbound allow-list.                           |
| `CLAUDE_PROMPT`         | *(empty)*                          | Prompt sent to Claude on launch.                               |
| `WORKSPACE_MOUNT`       | `$PROJECT_DIR:/workspace`          | How the project dir is bind-mounted.                           |
| `WORKSPACE_PATH`        | `/workspace`                       | Where the project dir appears inside the container.            |
| `MEMORY_LIMIT`          | `8g`                               | `--memory` arg.                                                |
| `PIDS_LIMIT`            | `4096`                             | `--pids-limit` arg.                                            |
| `CPU_LIMIT`             | *(empty)*                          | `--cpus` arg if set.                                           |
| `EXTRA_DOCKER_ARGS`     | `()`                               | Bash array of extra `docker run` arguments.                    |

## Optional: generic session conventions

`docker-claude/system-prompt.md` ships alongside the launcher. It
documents cross-project conventions that don't depend on your
domain:

- The **two-file memory split** — keep session state in
  `<project>.memory.md` next to your source, not in Claude's opaque
  auto-memory system.
- **Mandatory session phases** — refactor → domain work → docs
  refactor.
- **Continuous-run mode** — when the user says "run until usage
  is above X%", Claude self-paces back-to-back sessions against
  `docker-claude/usage.sh` without waiting for per-session approval.
- **End-of-session checklist** — what the memory update should
  cover before wrapping.

Loading it is opt-in — `config.example` references it in the
default `CLAUDE_PROMPT`, but you can drop the reference if your
project's own playbook covers the same ground. The file is
deliberately domain-agnostic so multiple `docker-claude` projects
can share it verbatim.

## Usage utilization helper

`docker-claude/usage.sh` prints your Claude Code 5-hour session-limit
utilization as a number (0-100), reading from
`~/.claude/.credentials.json`:

```
$ ./docker-claude/usage.sh            # 5-hour window
$ ./docker-claude/usage.sh --seven    # 7-day window
$ ./docker-claude/usage.sh --json     # full JSON response
```

Useful for `run until usage is above X%` loops, or just to check
how much headroom remains before your session limit kicks in.

## Known limitations

- `--dangerously-skip-permissions` is used inside the container. The
  firewall + cap-drop + no-new-privileges + isolated creds are the
  defense-in-depth against that; the trade-off is that Claude can
  run anything inside the sandbox without per-tool prompts.
- The firewall resolves allow-list domains once at container start.
  If an allowed domain's IPs rotate mid-session, new IPs won't be
  reachable until the container is restarted.
- `NET_ADMIN` is present in the container at all times (needed for
  the initial firewall config). The uid-change-clears-caps behavior
  means unprivileged processes inside can't use it, but anything that
  runs as root inside the container can.
- First-run login is interactive — subsequent runs are silent.

## Security model in one paragraph

Untrusted code running as `dev` inside this container can read/write
the mounted project dir (that's the point — it's Claude doing work),
can reach only allowed outbound hosts, cannot elevate privileges,
cannot reprogram the firewall, cannot escape via setuid binaries,
cannot fork-bomb the host, and cannot see the host's Claude session
(`~/.claude`) or any other project's Claude session. It *can*
exhaust `MEMORY_LIMIT` bytes of RAM and `PIDS_LIMIT` processes; tune
those to your host.
