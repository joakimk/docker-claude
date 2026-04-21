# docker-claude system prompt

Generic playbook for running Claude Code sessions inside a
`docker-claude` container. This file is **optional** — your project
can point `CLAUDE_PROMPT` wherever you want. But if you load this
alongside your project-specific playbook, the two compose: this file
sets the cross-project conventions, yours sets the domain ones.

## The two-file split (procedure vs state)

Keep session knowledge in **exactly two files** per project, next to
your source:

- **`<project>.md`** — procedure. Rules, gates, phase order. Rarely
  changes between sessions. This is the playbook you follow.
- **`<project>.memory.md`** — state. Current baselines, findings,
  user preferences, rolling session log. Updated every session.
  This is the single source of truth for what has been learned.

**Never** write session state to Claude Code's auto-memory system
(`~/.claude/projects/*/memory/`). The whole point of the two-file
split is that state lives *next to the code* — it's reviewable in
PRs, diffs when pruned, and readable by the next session without
trusting an opaque memory daemon.

When the two files disagree, memory wins for *numbers* (baselines,
findings), procedure wins for *rules* (gates, phases). If a
procedural rule becomes obsolete, fix the procedure file; if a memory
entry becomes obsolete, prune it.

## Session orientation (do this FIRST, every session)

1. **Read `<project>.memory.md`.** It has current state, recent
   session details, findings, and the "what to try next" handoff from
   the previous session.
2. **Verify baselines** (or whatever the project's equivalent "known
   good" check is). If current measurements don't match memory, stop
   and investigate before changing anything.
3. **Read the previous session's "What to try next" list.** Prefer
   handed-off items over re-running exploration you already did.
4. **Declare your testing path.** Either "Writing tests first: [what]"
   OR `BREAKING RULE: [rule] because [reason]`. Breaking-rule
   declarations are fine when the rule doesn't fit — just state it
   up front so the trail is legible.

## Mandatory session phases

Each session follows a fixed order. Don't skip phases; don't reorder
them.

### 1. Refactor (before any new work)

At least one small refactor edit lands before touching the domain
work. Leave the repo cleaner than you found it. Rules:

- **Behavior-preserving.** Whatever your project's "known good"
  verification is (bit-identical stats, golden files, passing tests,
  etc.) must hold before/after.
- **Tests pass.** Extracted helpers get their own unit tests.
- **Spend 20-30% of session time** on this, not "5 minutes". The
  maintainability compounding is the point.
- If after 30 min you genuinely find nothing worth refactoring, write
  a paragraph in memory explaining what you considered and rejected.
  "Didn't have time" is not acceptable.

### 2. Domain work (the actual goal of the session)

Whatever the project's main loop is — experiments, feature
implementation, bug fixing, whatever. Stay within the scope the user
set. Don't scope-creep into fixing unrelated things.

### 3. Documentation refactor (before ending)

Every session ends by refactoring the memory file itself.

Rules:
- **Prune stale entries.** A finding superseded by a later session
  either gets removed or demoted to a "Historical" section with a
  one-line note about what superseded it.
- **Age out details.** Old full-detail session entries age out of
  "Detailed recent sessions" after ~3 sessions; the one-liner in the
  session log stays.
- **Fix procedure drift.** If a rule in the procedure file is no
  longer how we actually work, fix it. Don't let playbook and reality
  diverge silently.
- **Target readability.** Both files together should stay readable in
  one session. If either grows past ~1500 lines, prune more
  aggressively.

Commit this refactor alongside the session's main work; don't ship it
as a drive-by.

## Ending a session — memory update checklist

Before wrapping:

- [ ] Refactor landed (one concrete file edit, behavior-preserving).
- [ ] Domain work complete to the scope the user set.
- [ ] Tests green (`cargo test`, `pytest`, whatever the project uses).
- [ ] Baselines in memory updated if they shifted intentionally.
- [ ] New session entry in "Detailed recent sessions" (newest first).
- [ ] New one-liner in the session log (newest first).
- [ ] Oldest full-detail session demoted to a one-liner — keep only
      the last ~3 in full detail.
- [ ] Findings / rejections updated with today's verdicts.
- [ ] "What to try next session" list — always include ≥3 items,
      categorized by priority (live gap, follow-ups, meta-process,
      refactor targets).
- [ ] Docs refactor landed (the phase 3 above) — pruned stale
      entries, fixed drift, split or merged sections if they grew.

## Continuous-run mode

When the user asks you to "run until usage is above X%" (or "run
continuously until X", "keep going until Y"), interpret this as an
instruction to **self-pace multiple back-to-back sessions**.

- Check usage with whatever the project exposes (`docker-claude/
  usage.sh` is the standard helper; it reports the 5-hour session-
  limit utilization as a number).
- After each session wraps its memory update, run the usage check.
- If below the target, immediately start the next session — re-verify
  baselines, pick new experiments / tasks / targets, refactor, update
  memory. Treat each loop as a fresh full session.
- **Do not wait for user approval between sessions.** The user
  authorized the loop up front; pausing to ask defeats the point.
- If something unexpected happens (baseline mismatch, failing tests
  with unclear cause, ambiguous next step), stop the loop and
  surface the question — but don't pre-emptively stop just to check
  in.
- If usage has risen above the target, stop and report.

The 5-hour window can roll over mid-loop — `usage.sh` can reset from
52 → 3 unexpectedly. That's normal; the loop exit condition is
"above target", so resetting extends the run. If the user wants a
fixed number of sessions, they'll say so.

## Anti-patterns (don't do these)

- **Writing session state to Claude's auto-memory** instead of the
  project memory file. Auto-memory is not reviewable and leaks
  across projects.
- **Ending a session without a docs refactor.** The memory file
  grows monotonically otherwise.
- **Skipping baseline verification at the start of a session.** You
  will waste an hour chasing a "regression" that was a stale
  environment.
- **Letting refactors bundle with domain changes.** Each phase commits
  separately so bisects stay clean.
- **"Fixing" something unrelated mid-session.** If you spot another
  bug, note it in memory's "what to try next" and leave it. Keep
  the blast radius small.

## How to reference this file from your project

In your `docker-claude.config`:

```bash
CLAUDE_PROMPT="Read docker-claude/system-prompt.md and docs/<project>.md, then resume work."
```

Or if you have a more complex startup:

```bash
CLAUDE_PROMPT="Read docker-claude/system-prompt.md, docs/<project>.md, and docs/<project>.memory.md, then resume work."
```

You can also skip loading this file — nothing forces it. But if you
have multiple docker-claude projects, the cross-project conventions
belong here so you don't re-derive them in each project's playbook.
