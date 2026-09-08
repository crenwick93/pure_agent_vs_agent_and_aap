# Specification: aap-token-bench

Read this before writing any code. It explains what is being measured, why the
design is the way it is, and which shortcuts will invalidate the result.

## What this is

A benchmark that measures the token cost of completing one identical task two
ways:

| | Tool surface | Does the work |
|---|---|---|
| **Arm A** (control) | shell + AWS CLI on a workstation | itself, step by step |
| **Arm B** (treatment) | AAP MCP server only | by launching a job template |

Both arms create a real EC2 sandbox that satisfies the same checks. The output
is a token count, a cost, and a crossover point.

## Why anyone should care

The MCP server for Red Hat Ansible Automation Platform went GA in June 2026.
Red Hat's public position is that routing agents through AAP helps manage token
and compute cost. There is no published measurement behind that claim. This
repo supplies one, and lets anyone re-run it against their own controller.

## The hypothesis

An agent loop resends its whole conversation on every turn. An agent that runs
commands must read the output of each command to know whether it worked, so
that output lands in context and is paid for again on every later turn. Cost
grows faster than linearly with the number of steps.

An agent that launches a job template reads a status instead of evidence. The
playbook output stays in the controller. Its context stays flat.

**But Arm B is not cheaper from turn one.** It pays a large fixed cost: the MCP
tool definitions, plus the job template catalog it reads to decide what to
launch. Both sit in context and are re-read on every turn. There is a crossover
point. Finding and publishing it is a primary output of this project, not a
footnote.

## The task

A developer types this into Cursor:

> I need a RHEL 9 sandbox for the payments team with Postgres 16 and 8 GB of
> RAM. Tear it down after a week.

Delivered means all of the following are true on the instance:

1. Running RHEL 9, instance type with at least 8 GB RAM
2. PostgreSQL 16 installed, enabled and running
3. Security group permits SSH and Postgres from the developer CIDR only
4. Tagged `team=payments`, `ttl_days=7`, `managed_by=<arm>`
5. Registered in the CMDB stub (a JSON file or an HTTP endpoint, your choice)
6. Password auth and root SSH login disabled

These are checked by `scripts/verify.sh`, which runs after both arms and knows
nothing about how the state was reached.

## Non-negotiable design rules

Violating any of these makes the numbers worthless. Do not "simplify" past them.

1. **One variable only.** Same model, same temperature (0), same system prompt,
   same task wording, same AWS region and account, same verification. Only the
   tool list differs.

2. **Never name the mechanism in the prompt.** No "Ansible", "AAP", "job
   template", "playbook". Describe the end state. The moment the prompt names a
   template, Arm B stops being an agent and Arm A is being asked to do something
   it has no route to.

3. **Do not strawman Arm A.** It gets what a competent engineer would actually
   give a coding agent: shell access on a workstation with the AWS CLI
   configured and an SSH key. That is a fair primitive. If a reviewer can argue
   the control was handicapped, the whole project is dismissed.

4. **Reset between every episode.** Terminate instances, delete the CMDB entry,
   remove security groups. If run 2 starts from run 1's leftovers the numbers
   are junk.

5. **Repeat and report spread.** Five runs per arm minimum. Agent trajectories
   vary a lot. Report median plus min/max and a coefficient of variation. If
   Arm A's spread is wide and Arm B's is narrow, that is a finding about
   predictability and it may matter more than the medians.

6. **Caching off by default.** Set no `cache_control` anywhere. Run a second
   warm configuration separately and report both. Caching does not change token
   counts, only the price of the repeated prefix, and it helps Arm A within a
   session.

7. **Count only verified runs** in the headline number, and report the success
   rate separately. Cost per successful sandbox is the honest metric, not cost
   per attempt.

## Measurement

Per episode, record: input tokens, output tokens, cache read/write tokens, turn
count, tool call count, wall clock, verification pass/fail, and the fixed token
cost of the tool definitions alone (via `count_tokens` with and without tools).

Report token counts as the primary result and money as derived, with the rate
stated. Token prices fall; token counts do not.

## Arm A tool surface

Three tools, deliberately primitive:

- `run_command(command)` — runs on the workstation. The AWS CLI is configured
  and an SSH key is present, so this covers both `aws ec2 ...` and
  `ssh ec2-user@...`.
- `read_file(path)` — local file read.
- `list_ssh_targets()` — returns instances the agent has created this session.

Return real stdout, stderr and exit code. Do not truncate. The verbosity is the
thing being measured.

## Arm B tool surface

Whatever the AAP MCP server exposes, pulled live at connect time via
`list_tools` rather than hardcoded. The tool definition overhead is a real cost
of this architecture and must be measured, not assumed away.

Arm B must discover the template itself. Do not pass a template ID in config.

## The AAP side

`aap/` holds what has to exist in the controller, as configuration-as-code
where possible:

- A **Developer Self-Service** organization
- **20 job templates**, each with a description written for a model to read and
  a survey defining typed variables. 20 is a scoped developer catalog, not a
  claim about a typical estate. Say so in the article.
- One of them, `provision-dev-sandbox`, actually provisions EC2 via
  `amazon.aws`. The other 19 are realistic neighbours so the agent has a genuine
  selection problem: `refresh-db-from-prod`, `rotate-dev-credentials`,
  `extend-sandbox-ttl`, `teardown-sandbox`, and so on.
- An AWS credential in the controller. **Arm B never sees it.**

Template descriptions are a machine interface here, not documentation. "Builds
a sandbox" tells a model nothing about when to pick it over the four adjacent
templates. Say what it does, when to choose it, what it will not do, and what
it needs.

## Repo layout

```
harness/
  harness.py        agent loop, token accounting, orchestration
  report.py         aggregation, crossover, chart
  config.yaml       model, task text, AWS settings, pricing
scripts/
  verify.sh         the six checks, exit 0 = delivered
  cleanup.sh        terminate instances, remove SGs, clear CMDB
aap/
  templates/        job template definitions + surveys
  README.md         how to load them into a controller
widget/
  context-growth.html   embeddable interactive for the article
results/            harness output, gitignored except examples
article-draft.md    the write-up, with [[PLACEHOLDER]] figures
```

## Cost and safety

Each run creates a real instance. A t3.large for ten minutes is pennies, and
ten runs is still pennies, but a failed run that leaves an instance up is not.

- Tag everything `benchmark=aap-token-bench` at creation.
- `cleanup.sh` terminates by tag and runs in a `finally`, not on the happy path.
- Add a sweeper that terminates any tagged instance older than an hour.
- Use a dedicated AWS account or a hard budget alarm.
- Arm A holds AWS credentials by design. Use a scoped IAM role limited to EC2
  in one region, not an admin key.

## What "done" looks like

- `python harness/harness.py --arm both --runs 5` completes and writes JSONL.
- `python harness/report.py results/*.jsonl` prints the table, the A/B ratio per
  turn, the crossover, and writes the chart.
- No orphaned AWS resources afterwards.
- `article-draft.md` placeholders can all be filled from `summary.json`.

## Things that will go wrong

- **The MCP server may return full job stdout rather than a summary.** Check
  this manually on one call before trusting any number. If it dumps the log,
  you have measured an MCP implementation, not an architecture.
- **Arm B polling.** Every status poll is another full context re-read. Count
  polls; a chatty poll loop is a real cost.
- **Arm A may fail outright** on some runs. That is a result, not a bug. Record
  it and report the success rate.
- **`max_turns`.** Arm A needs headroom. If it hits the ceiling, that is data.
