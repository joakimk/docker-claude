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

1. **Budget gate (BEFORE any other work).** If the continuous-run
   marker file exists, check whether this fire is allowed to proceed
   before reading memory, verifying baselines, or doing anything else.
   Run `docker-claude/usage.sh` and `docker-claude/usage.sh --json`.

   a. **Weekly gate.** Compute `elapsed_fraction = (now -
      (seven_day.resets_at - 7d)) / 7d`. If
      `seven_day_utilization ≥ elapsed_fraction × 100` → SKIP.

   b. **Determine fire type** from current time vs `resets_at`:
      - If `now < resets_at - 30min` → this is a **mid-window
        startup** (e.g. container restart). The budget for this
        window is the normal-fire 30%. If `five_hour_utilization
        ≥ 30%` → SKIP; the normal fire already consumed its budget
        and the spare-resources window hasn't arrived. Arm both
        crons (spare at `resets_at - 30min`, normal at
        `resets_at + 5min`) and stop.
      - If `resets_at - 30min ≤ now < resets_at` → this is a
        **spare-resources fire**. If `five_hour_utilization ≥ 70%`
        → SKIP. Otherwise proceed, targeting 90%.
      - If `now ≥ resets_at` (new window) → this is a **normal
        fire**. Proceed, targeting 30%.

   c. **On SKIP:** log one line to the project memory file's session
      log (`"S<N>-skipped (YYYY-MM-DD): <reason> — X% used"`),
      re-arm both crons from current `resets_at`, and STOP. Do not
      read memory, verify baselines, or start any session work.

   d. **On PROCEED:** note the target ceiling (30% or 90%) and
      continue to step 2.

2. **Read `<project>.memory.md`.** It has current state, recent
   session details, findings, and the "what to try next" handoff from
   the previous session.
3. **Start with a clean build / app environment launch.** Before any
   other work, build the project (or launch its app environment) and
   confirm it comes up cleanly — no compiler warnings, no lint noise,
   no deprecation notices, no startup errors. A dirty environment
   masks real problems and drifts silently over time; new warnings
   blend into old ones and the signal for "something broke" is lost.
   If warnings are present, fix them first or record in memory why
   they can't be fixed this session. Don't normalize noise.
4. **Verify baselines** (or whatever the project's equivalent "known
   good" check is). If current measurements don't match memory, stop
   and investigate before changing anything.
5. **Read the previous session's "What to try next" list.** Prefer
   handed-off items over re-running exploration you already did.
6. **Declare your testing path.** Either "Writing tests first: [what]"
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

Check usage with `docker-claude/usage.sh` (reports 5-hour OAuth
utilization as a number) and `docker-claude/usage.sh --json` for
`resets_at` and weekly utilization fields.

### Default budget: 30% of 5-hour window + weekly-progress gate

When no explicit number is given, each continuous run consumes the
first **30%** of the current 5-hour OAuth window. Plan session
count by estimating ~15-20% per full session (refactor +
experiments + memory update); continuous runs typically fit 1-2
full sessions before wrapping.

**7-day-progress gate (hard stop before starting a new run).**
Before launching a scheduled / continuous run:

```
elapsed_fraction = (now - (seven_day.resets_at - 7d)) / 7d
```

Proceed only if `seven_day_utilization < elapsed_fraction × 100`.
If weekly is ahead of pace, SKIP this run entirely — log one line
to the project memory file's session log (`"S<N>-skipped
(YYYY-MM-DD): weekly gate — X% used / Y% elapsed"`), reschedule,
no other work. Don't burn through the weekly cap.

### Two-fires-per-window schedule

When running a scheduled loop (via `CronCreate` one-shots or
equivalent), fire **twice per 5-hour window**:

1. **Normal fire** at `five_hour.resets_at + 5min` — first 30%
   of new window. Five-minute buffer avoids racing the server-side
   reset boundary.

2. **Spare-resources fire** at `five_hour.resets_at - 30min` (30
   minutes before the CURRENT window ends). Behavior:
   - If weekly gate fails → SKIP.
   - If current 5-hour utilization ≥ 70% → SKIP (normal fire will
     handle next window).
   - Else → run session(s) until usage ≥ **90%**, reclaiming
     unused budget that would otherwise expire.
   - The 30-min buffer is the hard deadline; stop naturally when
     the window closes. Leave 10% (90→100) margin to avoid
     accidentally hitting the cap.

After each fire (normal or spare, including skipped), re-fetch
`resets_at` and schedule BOTH the next normal AND next spare as
one-shot crons. This keeps the loop adaptive across reset shifts.

### Cross-restart persistence: marker file

`CronCreate` and `ScheduleWakeup` are session-only — the job dies
when Claude Code exits. To survive restarts, a continuous run
writes `tmp/continuous-run.enabled` (or the project's equivalent
path under a gitignored dir). Session orientation's **budget gate**
(step 1) checks for this marker on every startup; if present AND
no cron armed in the current session, it runs the budget check and
either proceeds (if within budget) or SKIPs (if budget consumed),
then re-arms both crons from the current `resets_at`. The budget
gate prevents mid-window restarts from starting work when the
normal-fire 30% has already been consumed. Delete the marker on
explicit stop; don't delete on weekly-gate-skip (a skip is a
scheduling decision, not a loop disable).

### Clean-stop rules (hard rules)

Only legitimate reasons to wrap a normal fire under 30% (or spare
fire under 90%):
- Usage reports ≥ target.
- Current experiment is mid-long-running-step (MC, build, test
  batch) and the next would push over target.
- User explicitly tells you to stop.
- Every handoff item AND every reasonable neighboring tweak on
  each has been exhausted AND each is documented with a written
  justification in the memory entry.

"Experiments came up empty", "all rejections", "nothing more to
try" are NOT valid stop reasons. Negative findings are useful —
document them and keep going. If about to wrap under budget:
probe narrower neighbors of the last rejected candidate, sweep a
different parameter, try a different component, or pull a
lower-priority handoff item.

### Keep-going corollary

If something unexpected happens mid-loop (baseline mismatch,
failing tests with unclear cause, ambiguous next step), stop the
loop and surface the question — but don't pre-emptively stop just
to check in. The user authorized the loop up front.

The 5-hour window can roll over mid-loop — `usage.sh` can reset
from 52 → 3 unexpectedly as old calls age out. That's normal; the
loop exit condition is the threshold (30% normal, 90% spare), so
resetting extends the run. If the user wants a fixed number of
sessions, they'll say so.

## Decision authority (agent decides, documents, doesn't escalate)

The user does not want to be asked to make small tuning decisions.
When a candidate change passes some checks cleanly and fails others
marginally, DECIDE yourself, document the reasoning, and either
apply or reject. Don't flag candidates back to the user as
"decision points" unless the outcome has large-scope consequences
(breaking existing behavior, deleting code, changing published
interfaces, etc.).

Each project should define its own concrete decision framework in
its playbook — numeric thresholds, which validation gates must pass,
how to rank competing candidates. The framework lives in the
project playbook; this file just states the meta-rule: **decide
and document**.

Record the applied rule + reasoning in the relevant commit message
/ code comment / memory entry, so future sessions can audit the
decision trail without needing to ask the user.

## Parallelism defaults

Up to **nproc / 2 tool calls may run in parallel** (= 12 on a
24-core box, 8 on a 16-core box, 4 on an 8-core box) when they are
independent and doing so saves real time (bulk reads, independent
greps, launching multiple experiments). Beyond that cap, run
sequentially to keep cognitive load and system load sane. If
something depends on a previous result (edit after read), run
sequentially — don't batch speculatively.

**Inner parallelism (scripts + compiled code) is not capped at the
outer cap.** The nproc/2 limit is about your tool-call batching, not
what a single tool does under the hood. Project scripts using
`max(1, 0.8 × nproc)` (= ~19 on a 24-core box) stay nproc-bounded —
don't throttle them to the outer cap. If writing a new parallel loop,
nproc-bounded is the right ceiling; the two bounds are independent.

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
