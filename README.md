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

This pushes the 20 job templates, credentials, project, and inventory into your
AAP controller. You should see them appear under the **Developer Self-Service**
organization.

## Running the test

Both arms use the same prompt. Describe the end state — never mention Ansible,
AAP, or job templates:

> Provision a new RHEL10 instance on AWS in eu-west-1

**Important: run both tests from an empty folder, not from this repo.** If the
agent can see the playbooks, vars files, or this README, it has the answer
before it starts. Open Cursor in an empty directory (e.g. `mkdir ~/bench-test
&& cd ~/bench-test`) so each agent starts with nothing but the one-liner and
its tools.

### Arm A — pure agent (shell access)

Disable the AAP MCP server so the agent only has shell tools. In Cursor, open
**Settings** (⌘ + ,) → **MCP**, find the AAP server, and toggle it off. Open
a new Cursor chat in the empty folder. Give it the prompt and let it work. It will provision the instance, SSH in to configure it, install
packages, harden SSH, set up the security group, and register in the CMDB —
all step by step.

When it finishes, open the **Context Usage** panel at the bottom of the chat
and screenshot the token breakdown. Record: total context, conversation
tokens, turns, and tool calls.

### Arm B — agent + AAP MCP

Re-enable the AAP MCP server. Open a new Cursor chat in the same empty folder.
Give it the same prompt. The agent will list available templates, pick
Provision Dev Sandbox, fill in the survey variables, launch the job, and read
the status.

Screenshot the Context Usage panel again. Record the same metrics.

### After each run

```bash
# Verify the sandbox meets all six conditions
./scripts/verify.sh <instance-id>

# Clean up — always run this, even if the test failed
./scripts/cleanup.sh
```

Sandboxes are tagged with `ttl_days` but are not automatically terminated in
this demo. In production, a scheduled AAP workflow (using the
`teardown-sandbox` template in the catalog) would sweep instances past their
TTL and terminate them. For this demo, `cleanup.sh` is the safety net — run it
after every test.

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
| Turns | ~14 | ~4 |
| Tool calls | ~14 | ~3 |
| Context growth | Superlinear (command output accumulates) | Flat (playbook output stays in controller) |
| Credential exposure | Agent holds AWS keys | Controller holds credentials |

## Layout

| Path | What |
|---|---|
| `SPEC.md` | Design, rules, pitfalls |
| `aap/cac/` | Configuration-as-code for the 20 templates |
| `playbooks/` | The real provision playbook |
| `scripts/` | Verification and AWS cleanup |
| `widget/` | Embeddable interactive for the article |
| `article-draft.md` | The write-up with `[[PLACEHOLDER]]` figures |
