# What has to exist in your controller

Arm B talks only to the AAP MCP server. For the benchmark to mean anything,
the controller needs a realistic catalog, not one template sitting on its own.

## Quick start

```bash
# Install collections
ansible-galaxy collection install -r aap/cac/requirements.yml

# Fill in .env with your AAP and AWS credentials
cp .env.example .env

# Apply everything to your controller
./aap/scripts/cac-apply.sh
```

## What gets created

- **Organization**: Developer Self-Service
- **Credentials**: AWS credential, SSH key (from env vars)
- **Project**: points at this repo for the provision playbook
- **Inventory**: AWS EC2 dynamic inventory filtered by `benchmark=aap-token-bench`
- **20 job templates** with model-readable descriptions and typed surveys

Five of those templates have real playbooks: Provision Dev Sandbox, Open
Firewall Port, Check Sandbox Health, Restart App Services, Tail App Logs. The
other 15 are placeholders so catalog search is still a 20-item problem. The
session test only launches the five real ones.

## Templates

20 templates. That number is a scoped developer catalog, not a claim about a
typical estate, and the article should say so.

Only five templates have real playbooks. The other 15 use `playbooks/placeholder.yml`.
They exist so the agent has to search a 20-item catalog. Without them, template
selection is a trivial lookup and the catalog tax disappears from the measurement.

```
provision-dev-sandbox      extend-sandbox-ttl        teardown-sandbox
refresh-db-from-prod       rotate-dev-credentials    seed-test-data
snapshot-sandbox           restore-sandbox           resize-sandbox
attach-shared-volume       grant-temp-db-access      rebuild-app-config
run-integration-suite      sync-secrets              open-firewall-port
tail-app-logs              restart-app-services      check-sandbox-health
list-team-sandboxes        report-sandbox-spend
```

## Why 20?

Every template description the MCP token can see is read into context and paid
for on every turn. RBAC scoping is a cost control as much as a security one.
Scope the MCP token to this org so the agent only sees these 20, not the full
estate.

## Descriptions are a machine interface

Cover four things: what it does, when to choose it, what it will not do, and
what it needs. See `aap/cac/vars.yml` for all 20.

## Credential

The AWS credential lives in the controller. Arm B never sees it, and that is
the point: Arm A needs AWS keys on the workstation to do the same job.
