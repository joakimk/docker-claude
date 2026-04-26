# docker-claude

This is a toolset to run claude fully automatically without it asking
for permission by putting it inside a locked down docker container.

This toolset and system-prompt could potentially be used with any LLM
coding tool, and at that point it would make sense to rename it.

**WARNING: Only use this if you know what it all does and accept any risks.**.
There might still be security issues to consider. Don't let this have access to any sensitive data.

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
