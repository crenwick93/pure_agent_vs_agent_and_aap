# Measure what an AI agent costs with and without Ansible Automation Platform

The MCP server for Red Hat Ansible Automation Platform became generally available in June 2026. It lets an AI tool such as Cursor or Claude query your automation controller and launch jobs from a chat prompt. One of the stated reasons to route agents through the platform is cost, specifically choosing when to spend tokens on reasoning and when to hand the work to automation that already exists.

I wanted a number behind that, so I ran the same request two ways and measured it.

A note on scope. These figures come from my lab, with my catalog and my playbooks. Your estate will produce different ones. The method is the useful part, and the harness is on GitHub if you want to point it at your own controller.

## The request

A developer needs a sandbox. In Cursor, they type:

> I need a RHEL 9 sandbox for the payments team with Postgres 16 and 8 GB of RAM. Tear it down after a week.

The host counts as delivered when it is registered, has Postgres running, has the firewall configured, is recorded in the CMDB, and has a teardown date set.

## Two ways to answer it

The first agent gets shell access and nothing else: `run_command` over SSH, `read_file`, and `list_inventory`. It builds the sandbox itself.

The second agent gets the AAP MCP server and nothing else. It can list job templates, launch one, and check the result. In my lab those templates sit in a single organization with 20 of them, each with a description and a survey.

Why 20? A mid-size IT self-service catalog typically has 40–60 items across all of IT. A single developer team's view, scoped by RBAC, is closer to 15–25: provision a sandbox, refresh a database, rotate credentials, open a firewall port, and so on. Twenty is a realistic scoped catalog, not a claim about a typical estate. If anything it understates what a production controller would expose, which means the token savings in the real world would be larger — more templates to read, but the agent still only launches one.

Same model, same temperature, same prompt wording, same hypervisor, same definition of done. The tool surface is the only thing that changes.

NOTE: Do not mention Ansible, AAP, or job templates in the prompt. If you do, you have handed the second agent the answer and asked the first one to do something it has no route to. Describe the end state and let each agent work out how to get there.

## What the shell agent does

It works, and it takes a while. Fourteen turns in my run, roughly what you would do by hand:

```plaintext
virsh list --all
virt-install --name dev-sbx-0142 --memory 8192 --vcpus 4 ...
subscription-manager register ...
dnf module enable postgresql:16
dnf install postgresql-server
postgresql-setup --initdb
systemctl enable --now postgresql
firewall-cmd --add-service=postgresql --permanent
```

Two things stand out when you read the transcript.

The `dnf install` step alone put [[TOKENS-DNF]] tokens into the context window. That is the transaction table, every dependency listed. Nobody chose to put it there. It arrived because the agent had to run the command to find out whether it worked, and the output came back attached.

The agent also invented its own teardown. It wrote a cron job. That is a reasonable thing to do and it is not what my template does, which matters if you ever need to explain to an auditor how sandboxes get removed.

## What the AAP agent does

Four turns. It lists the templates, picks one, launches it with variables taken from the request, and reads the result.

```plaintext
launch_job(
  template="provision-dev-sandbox",
  extra_vars={rhel_version: 9, memory_gb: 8,
              packages: [postgresql16], team: payments,
              ttl_days: 7}
)

job 4471: successful. dev-sbx-0142
```

The playbook output never enters the conversation. The agent does not read several hundred lines of Ansible to work out whether the job worked, it reads a status. It also never holds the subscription credential, because the controller runs the job and the controller owns the credential.

## The numbers

Five runs per arm, [[MODEL]] at temperature 0, prompt caching off, only verified runs counted.

| | Shell agent | AAP agent |
|---|---|---|
| Input tokens (median) | [[TOKENS-A]] | [[TOKENS-B]] |
| Turns | 14 | 4 |
| Wall clock | [[WALL-A]] | [[WALL-B]] |
| Verified successes | [[OK-A]]/5 | [[OK-B]]/5 |

At [[RATE]] per million input tokens, that is [[COST-A]] against [[COST-B]] per sandbox.

## Where it flips

The AAP agent is not cheaper from the first turn. Reading a catalog of 20 templates is the single largest thing it puts in context, and it pays for that on every turn afterward. For the first [[CROSSOVER]] turns of this task, the shell agent is ahead.

That is worth knowing rather than hiding. It means the saving is not a property of AAP, it is a property of the task being long enough for the shell agent's own output to outweigh the catalog. Short, novel, one-off work is exactly where you should let an agent reason for itself.

It also means the size of the catalog an agent can see is a cost decision, not only a security one. A developer organization with 20 well-described templates is cheap to read. A service account that can see all 400 templates in your estate is not, and it pays that on every turn.

## What I did not measure

Prompt caching was off for both arms. Turn it on and the gap narrows, because the shell agent's growing history is a cacheable prefix within a session. Caching does not change the token count, only the price of the repeated part.

I also treated AAP as already present. If you are buying the platform to do this, the subscription belongs in your sums, and the playbook behind the template was written by someone.

## Wrap up

- The same request routed through a job template used [[RATIO]] fewer input tokens than an agent doing the work itself.
- The saving comes from not reading command output, not from AAP being faster.
- Below roughly [[CROSSOVER]] turns of work, the agent with a shell is cheaper. Route short and novel tasks to reasoning.
- Keep the catalog an agent can see scoped to what that team needs.
- Write template descriptions for a model to read, not a person. The agent picks from the description and the survey variables, so vague ones cost you accuracy and tokens.

The harness is at [[REPO-URL]]. It takes an API key, an AAP token, and about twenty minutes.
