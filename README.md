# Pure agent vs agent + AAP

Measures the token cost of completing one identical task two ways: an AI agent
with shell access doing the work itself, versus the same agent calling a job
template through the MCP server for Red Hat Ansible Automation Platform.

Read `SPEC.md` for the full design rationale.

## Prerequisites

- Cursor with the AAP MCP server configured
- AWS CLI configured with access to an open environment
- An AAP controller with MCP enabled
- An SSH key pair for EC2 instances (`aap-token-bench`)

## Setup

### 1. Create your `.env`

```bash
cp .env.example .env
```

Then fill in each value:

**`AAP_HOSTNAME`** — The URL of your AAP controller (e.g.
`https://aap.example.com`). This is the same URL you log into in your browser.

**`AAP_TOKEN`** — A personal access token from your controller. To create one:
go to your AAP web UI, click your username (top right) → **Personal Access
Tokens** → **Create Token**. Give it a description like "MCP benchmark" and
copy the token value. This is used by the CaC playbook to push templates into
the controller.

**`AAP_VALIDATE_CERTS`** — Set to `false` if your controller uses a self-signed
certificate (common in labs and demos). Set to `true` for production
controllers with valid TLS.

**`AWS_REGION`** — The AWS region to create instances in (e.g. `eu-west-1`).
Must match where your AWS CLI is configured.

**`AWS_ACCESS_KEY_ID`** / **`AWS_SECRET_ACCESS_KEY`** — Your AWS credentials.
These are stored as an AWS credential in AAP (so the playbook can provision
EC2) and are also used by the cleanup and verify scripts. If your AWS CLI is
already configured via environment variables or an IAM role, you can leave
these blank — the scripts will use whatever `aws` CLI auth is available.

**`SSH_KEY_NAME`** — The name of an EC2 key pair in your AWS region. To create
one:
1. Go to the AWS Console → **EC2** → **Key Pairs** → **Create key pair**
2. Name it (e.g. `aap-token-bench`), choose `.pem` format, and download it
3. Move the `.pem` file to `~/.ssh/` and lock down permissions:
   `chmod 600 ~/.ssh/aap-token-bench.pem`

Do **not** put the `.pem` file in this repo.

**`SSH_KEY_PATH`** — Path to the `.pem` file on your machine (e.g.
`~/.ssh/aap-token-bench.pem`). The CaC playbook reads this file and registers
it as a Machine credential in AAP, so the provision playbook can SSH into
instances. Arm A's agent also needs this key to SSH in manually.

### 2. Install Ansible collections and apply the CaC

```bash
ansible-galaxy collection install -r aap/cac/requirements.yml
./aap/scripts/cac-apply.sh
```

This pushes the 20 job templates, credentials, project, and inventory into the
**Default** organization (not a separate org). Five templates have real
playbooks: Provision Dev Sandbox, Open Firewall Port, Check Sandbox Health,
Restart App Services, Tail App Logs. The other 15 are placeholders so catalog
search is still a 20-item problem.

### 3. Prepare AWS networking (once)

```bash
./scripts/setup-aws.sh
```

Creates or reuses a default VPC and a security group named
`benchmark-sandbox-sg` in `$AWS_REGION`. Arm A's Cursor rule assumes that
group exists.

### 4. Empty test folder + Cursor rules

**Do not run the agent with this repo open.** If it can see the playbooks, it
already has the answer.

```bash
mkdir -p ~/bench-test/.cursor/rules
cp cursor-rules/arm-a-shell.mdc ~/bench-test/.cursor/rules/assistant.mdc
# Edit the key path / region in that file if yours differ.
```

Open Cursor in `~/bench-test`, not in this repo. Restart Cursor after swapping
the rule file.

## Running the test

The unit of work is a **session**: five requests in the **same chat**. A
developer does not provision and leave. They keep asking.

Record **conversation tokens** after each request (Context Usage panel at the
bottom of the chat). Ignore the ~13K of Cursor tool definitions — both arms
pay that. Plot conversation tokens vs request number. The crossover is the
result.

Never mention Ansible, AAP, or job templates in any message.

### The five requests

Send these one at a time. Wait until each finishes. Screenshot conversation
tokens after each.

1. > I need a RHEL 10 sandbox in eu-west-1 for the payments team with 8 GB of RAM. Install PostgreSQL, harden SSH, and tag it for teardown after 7 days.

2. > Open port 8080 from my current public IP.

3. > Check the sandbox is healthy.

4. > Restart PostgreSQL.

5. > Show me the last 50 lines of the PostgreSQL log.

### Arm A — pure agent (shell access)

1. Cursor **Settings** (⌘ + ,) → **MCP** → toggle the AAP server **off**.
2. Copy `cursor-rules/arm-a-shell.mdc` to `~/bench-test/.cursor/rules/assistant.mdc`.
3. Restart Cursor, open a **new** chat in `~/bench-test`.
4. Send all five requests in that chat. Do not start a new chat between them.

### Arm B — agent + AAP MCP

1. Toggle the AAP MCP server **on**. Point it at `/mcp/job_management` (not
   `/mcp`). In the MCP tool list, keep only:
   `job_templates_list`, `job_templates_launch_retrieve`,
   `job_templates_launch_create`, `jobs_retrieve`, `jobs_stdout_retrieve`.
2. Copy `cursor-rules/arm-b-aap.mdc` to `~/bench-test/.cursor/rules/assistant.mdc`.
3. Restart Cursor, open a **new** chat in `~/bench-test`.
4. Same five requests, same chat.

On success the agent should read job `status` and `artifacts.result`, not the
full playbook stdout. Survey `memory_gb` is the string `"8"`, not the integer 8.

### After each arm

```bash
./scripts/verify.sh <instance-id>   # after request 1
./scripts/cleanup.sh                # after the session, even if it failed
```

Sandboxes are tagged with `ttl_days` but are not auto-terminated in this demo.
`cleanup.sh` is the safety net.

### After you have numbers

Paste conversation tokens for requests 1–5 into `widget/context-growth.html`
(`CONFIG.steps[].a` and `.b`) and into the table in `article-draft.md`.

### A note on MCP token scoping

The MCP server inherits the RBAC permissions of the user who created the API
token. If your token belongs to an admin user, the agent will see every
template in the controller — not just the 20 this demo creates. That inflates
the context cost for Arm B and makes the comparison unfair.

For a fair test, create a dedicated user in AAP (e.g. `mcp-benchmark`), grant
them Execute and Read access to only the templates in the Default org, and
generate the API token from that user. The agent will then see exactly 20
templates, which is what the article claims.

For initial setup and testing, an admin token is fine — just be aware the
template list will be larger than expected.

## What to compare

| Metric | Arm A (shell) | Arm B (AAP MCP) |
|---|---|---|
| Conversation after request 1 | higher or lower — measure it | catalog tax is front-loaded |
| Conversation after request 5 | grows with stdout | grows with status + artifacts |
| Crossover | request number where A overtakes B | the figure the article plots |
| Credential exposure | Agent holds AWS keys | Controller holds credentials |

## Layout

| Path | What |
|---|---|
| `SPEC.md` | Design, rules, pitfalls |
| `aap/cac/` | Configuration-as-code for the 20 templates |
| `playbooks/` | Five real playbooks + stubs |
| `scripts/` | Verification and AWS cleanup |
| `cursor-rules/` | Arm A / Arm B Cursor rules to copy into the empty test folder |
| `widget/` | Embeddable session chart for the article |
| `article-draft.md` | The write-up with `[[PLACEHOLDER]]` figures |
