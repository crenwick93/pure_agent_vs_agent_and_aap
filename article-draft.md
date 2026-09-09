# What an AI agent costs when it does the work itself versus handing it to automation

The MCP server for Red Hat Ansible Automation Platform became generally available in June 2026. It lets an AI tool such as Cursor or Claude query your automation controller and launch jobs from a chat prompt. One of the stated reasons to route agents through the platform is cost — specifically choosing when to spend tokens on reasoning and when to hand the work to automation that already exists.

I wanted a number behind that, so I ran the same request two ways and measured what it did to the context window.

A note on scope. These figures come from my lab, with my catalog and my playbooks. Your estate will produce different ones. The method is the useful part, and the repo is on GitHub if you want to point it at your own controller.

## The request

A developer needs a sandbox. In Cursor, they type:

> Provision a new RHEL10 instance on AWS in us-east-1

The host counts as delivered when it is running and reachable.

## Two ways to answer it

**Arm A — the agent does it itself.** It gets shell access: AWS CLI, SSH, and standard Linux tools. It figures out which AMI to use, how to configure the security group, what packages to install, how to harden SSH, and how to tag the instance for teardown. Every command it runs produces output that goes into the context window. The `dnf install` transaction table, the AWS CLI JSON responses, the SSH session output — all of it becomes tokens the model has to carry for the rest of the conversation.

**Arm B — the agent delegates.** It gets the AAP MCP server and nothing else. It can list job templates, read their descriptions, launch one, and check the result. In my lab those templates sit in a single organization with 20 of them, each with a description and a survey. The agent reads the catalog, picks the right template, fills in the survey variables from the request, and launches. The playbook runs server-side. The agent never sees the Ansible output — it gets back a status.

Same model, same prompt wording, same definition of done. The tool surface is the only thing that changes.

## Why this matters

No real team would give an AI agent raw shell access to build production infrastructure — and they shouldn't. The comparison isolates one variable: **what happens to the context window when the agent has to execute steps itself versus delegating to automation that already exists.**

The raw shell arm is not how you would ship this. But measuring it tells you something important about where tokens actually go — and it leads to a conclusion that matters for anyone building AI into their operations: the agent cannot scale without automation behind it. Not because it is not clever enough, but because the context window is finite and every command output eats into it.

An agent that does everything itself hits the ceiling fast. An agent that delegates to tested, governed automation stays small, cheap, and predictable. That is not a nice-to-have. It is a constraint of how these models work.

## Why 20 templates?

A mid-size IT self-service catalog typically has 40–60 items across all of IT. A single developer team's view, scoped by RBAC, is closer to 15–25: provision a sandbox, refresh a database, rotate credentials, open a firewall port, and so on. Twenty is a realistic scoped catalog, not a claim about a typical estate. If anything it understates what a production controller would expose, which means the token savings in the real world would be larger — more templates to read, but the agent still only launches one.

NOTE: Do not mention Ansible, AAP, or job templates in the prompt. If you do, you have handed the second agent the answer and asked the first one to do something it has no route to. Describe the end state and let each agent work out how to get there.

## What the shell agent does

It works, and it takes a while. Roughly [[TURNS-A]] turns:

```plaintext
aws ec2 describe-images --filters "Name=name,Values=RHEL-9*" ...
aws ec2 create-security-group ...
aws ec2 run-instances --instance-type t3.large --image-id ami-... ...
ssh ec2-user@... "sudo dnf install postgresql16-server"
ssh ec2-user@... "sudo postgresql-setup --initdb"
ssh ec2-user@... "sudo systemctl enable --now postgresql"
ssh ec2-user@... "sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
```

Two things stand out when you read the transcript.

The `dnf install` step alone put [[TOKENS-DNF]] tokens into the context window. That is the transaction table, every dependency listed, every GPG key imported. Nobody chose to put it there. It arrived because the agent had to run the command to find out whether it worked, and the output came back attached.

The agent also invented its own teardown mechanism. That is a reasonable thing to do and it is not what my template does, which matters if you ever need to explain to an auditor how sandboxes get removed. With the template, teardown is a known, tested, auditable process. With the shell agent, it is whatever the model decided at the time.

## What the AAP agent does

[[TURNS-B]] turns. It lists the templates, picks one, launches it with variables taken from the request, and reads the result.

```plaintext
job_templates_list()
→ 20 templates, reads descriptions

job_templates_launch_create(
  id=48,
  extra_vars={rhel_version: 9, memory_gb: 8,
              packages: "postgresql16-server", team: "payments",
              ttl_days: 7}
)

jobs_retrieve(id=...)
→ status: successful
```

The playbook output never enters the conversation. The agent does not read several hundred lines of Ansible output to work out whether the job worked — it reads a status. It also never holds the AWS credential or the SSH key, because the controller runs the job and the controller owns the credentials.

## The numbers

[[RUNS]] runs per arm, [[MODEL]] at temperature 0, prompt caching off, only verified runs counted.

| | Shell agent | AAP agent |
|---|---|---|
| Total context (median) | [[CONTEXT-A]] | [[CONTEXT-B]] |
| Conversation tokens | [[CONV-A]] | [[CONV-B]] |
| Tool definitions | [[TOOLS-A]] | [[TOOLS-B]] |
| Turns | [[TURNS-A]] | [[TURNS-B]] |
| Tool calls | [[CALLS-A]] | [[CALLS-B]] |

At [[RATE]] per million input tokens, that is [[COST-A]] against [[COST-B]] per sandbox.

## Where the cost comes from

The saving is not about AAP being faster. It is about what goes into the context window and what does not.

The shell agent's context grows with every command because every stdout and stderr is appended to the conversation. By the time it finishes, the conversation slice alone is [[CONV-A]] tokens. The AAP agent's conversation slice is [[CONV-B]] — it sent a few API calls and received structured responses.

The AAP agent pays an upfront cost to read the catalog: 20 template descriptions and their surveys. That is real, and it is the single largest thing it puts in context. But it pays it once, and the templates are well under [[CATALOG-TOKENS]] tokens total. The shell agent overtakes that within [[CROSSOVER]] turns as its own command output accumulates.

This is not a quirk of this particular task. It is a property of the architecture. Any task where the agent has to run commands and read their output will fill the context window at a rate that scales with the number of steps. Delegation to automation collapses those steps into a single tool call with a structured response. The longer the task, the wider the gap.

## What I did not measure

**Prompt caching.** It was off for both arms. Turn it on and the gap narrows, because the shell agent's growing history is a cacheable prefix within a session. Caching does not change the token count, only the price of the repeated part.

**The cost of building the automation.** I treated AAP as already present. If you are buying the platform to do this, the subscription belongs in your sums, and the playbook behind the template was written by someone. The comparison assumes you already have automation and asks what it costs to put an agent in front of it.

**Governance.** The shell agent can do anything the AWS credentials allow. The AAP agent can only do what the templates expose. That is a security argument, not a cost one, but it is worth noting that the cheaper path is also the more governed one.

## The wider evidence

This is one test in one lab, but the pattern it shows is not isolated. A growing body of industry evidence says the same thing: most of what enterprises are calling AI use cases are automation problems, and treating them as AI problems is burning budget.

**Leaders are collecting hundreds of use cases — and most do not need an agent.** Cutter's CEO Insights 2025 found that enterprise engineering organisations have "hundreds of AI use cases in active development at any given time," but the gap between development and production is enormous. Most are stuck in what Cutter calls a proof-of-concept trap: a pilot succeeds in isolation, the investment splits across more pilots, and nothing crosses the production threshold [1]. An analysis of production AI deployments estimates that roughly 90 percent of them do not require dynamic agent orchestration — they are classification, extraction, summarisation, or API-call tasks that are fundamentally workflow problems dressed in agent clothing [2].

**Anthropic's own usage data confirms it.** The Anthropic Economic Index, based on a privacy-preserving analysis of one million API transcripts, found that 97 percent of tasks represented in enterprise API traffic show automation-dominant patterns. Seventy-seven percent of enterprise API transcripts were classified as automation rather than augmentation. The dominant use cases are routine back-office workflows: email management, document processing, scheduling, and code generation [3][4].

**The cost difference is not marginal.** For structured, high-volume tasks, deterministic automation runs at roughly $0.001–$0.005 per transaction. An AI agent performing the same work costs $0.02–$0.10 per transaction — ten to twenty times more. Gartner estimates that RPA delivers 30–200 percent ROI in the first year for structured, rule-based processes, a benchmark AI agents rarely match on pure repetition tasks because of their higher inference costs [5][6][7]. The premium buys reasoning. If the task does not need reasoning, it buys nothing.

**The budget is growing, but the ROI is not keeping up.** Writer's 2026 Enterprise AI Adoption survey of over 1,600 employees and executives found that 79 percent of organisations face challenges adopting AI — a double-digit increase from 2025 — and 59 percent invest over one million dollars annually in AI technology. Yet only 29 percent report significant organisational ROI. Fifty-four percent of C-suite executives admit that adopting AI is tearing their company apart [8].

**Gartner warns that over 40 percent of agentic AI projects will be cancelled by end of 2027**, typically because teams underestimate the cost, the oversight required, or both. The guidance is explicit: many enterprise tasks do not require reasoning, and deterministic automation is cheaper, safer, faster, easier to audit, and more predictable for those tasks [9].

**When organisations audit properly, the majority of recoverable value comes from process change, not AI.** A seven-day AI diagnostic at an Irish distributor identified €560,000 in recoverable value. The majority required workflow redesign using existing tools — not AI. Where AI was recommended, it was for specific, well-defined tasks only after the underlying process was stable. The workflow drift alone, fixable without AI, was worth €180,000 per year [10].

The context window test in this article gives you the mechanism. These figures give you the scale. Redirecting the automation-shaped use cases to actual automation — and reserving agent reasoning for the work that genuinely needs it — is not just an architectural preference. It is the difference between a programme that compounds and one that stalls.

## What this means for applied AI

There is a temptation to think of automation platforms and AI agents as alternatives — that the agent replaces the automation. This test shows the opposite, and the industry data confirms it: the automation is what makes the agent viable, and most of the use cases landing on leaders' desks are automation problems to begin with.

Without automation behind it, the agent fills its context window with command output, reinvents processes that already exist, and produces results that vary with whatever the model decides at the time. It works, but it is expensive, ungoverned, and fragile. It does not scale past one-off tasks. Multiply that by the hundreds of use cases an enterprise is trying to ship, and you have a programme that burns budget at ten to twenty times the rate it needs to.

With automation behind it, the agent becomes an interface layer. It takes a request in natural language, maps it to the right piece of tested automation, and delegates. The context window stays small. The process is repeatable. The credentials never leave the platform. The audit trail is the job log, not a chat transcript.

If you are building AI into operations — whether that is developer self-service, incident response, compliance, or anything else that touches infrastructure — the question is not whether to use an agent or automation. It is how quickly you connect the two. The agent without automation is a demo. The agent with automation is a product. And the fastest way to show ROI on your AI investment may be to redirect the automation-shaped use cases to the automation platform you already own.

## Practical advice

- **Route long, procedural tasks to automation.** If the agent would need more than a few tool calls to complete it, there should be a template behind it.
- **Keep the catalog scoped.** Twenty well-described templates is cheap to read. Four hundred is not, and you pay for it on every turn. Use RBAC to limit what the agent's token can see.
- **Write descriptions for a model, not a person.** The agent picks from the description and the survey variables. "Builds a sandbox" tells it nothing about when to pick this over the four adjacent templates. Say what the template does, when to choose it, what it will not do, and what it needs.
- **Route short and novel tasks to reasoning.** Not everything belongs in a template. The crossover point in this test was roughly [[CROSSOVER]] turns. Below that, the agent working alone is cheaper.
- **Measure your own estate.** The repo is at [[REPO-URL]]. Point it at your controller and see where your numbers land.

## References

[1] Axccelerate, "Why Enterprise AI Stalls: What the 13% Do Differently," citing Cutter Consortium CEO Insights 2025. https://axccelerate.com/blog/why-enterprise-ai-stalls-what-the-ready-do-differently

[2] M. Nasternak, "Agent Is Not What You Need," 2025. https://michalnasternak.medium.com/agent-is-not-what-you-need-1c48e37d9b22

[3] Anthropic, "Anthropic Economic Index report: Economic primitives," January 2026. https://www.anthropic.com/research/anthropic-economic-index-january-2026-report

[4] Anthropic, "Anthropic Economic Index report: Uneven geographic and enterprise AI adoption," arXiv:2511.15080, 2025. https://doi.org/10.48550/arxiv.2511.15080

[5] "AI Agents vs RPA: The Definitive Enterprise Decision Guide 2026." https://vitaloralife.com/ai-agents-vs-rpa/

[6] "AI Agents vs Automation: What Handles Complex Tasks," Zero In Daily. https://zeroindaily.com/ai-agents-vs-traditional-automation-complex-tasks/

[7] "AI Agents vs RPA: Which Should You Choose?" PUNKU.AI. https://www.punku.ai/blog/ai-agents-vs-rpa

[8] Writer, "Enterprise AI adoption in 2026: Why 79% face challenges despite high investment." https://writer.com/blog/enterprise-ai-adoption-2026/

[9] R. Singh, "The New Enterprise AI Operating Model," citing Gartner predictions on agentic AI project cancellations. https://www.raktimsingh.com/autonomy-allocation-enterprise-ai/

[10] Acuity AI, "How a Seven-Day AI Diagnostic Recovered €560K for an Irish Distributor." https://acuityai.co/blog/seven-day-ai-diagnostic-recovered-560k
