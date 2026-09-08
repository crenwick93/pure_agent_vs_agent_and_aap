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

## Templates

20 templates. That number is a scoped developer catalog, not a claim about a
typical estate, and the article should say so.

Only `provision-dev-sandbox` has a real playbook behind it — it actually
provisions an EC2 instance. The other 19 use the Demo Project's
`hello_world.yml` as a placeholder. They exist purely to fill out the catalog
so the agent has to read 20 descriptions and choose the right one, which is
what happens in a real estate. Without them, template selection is a trivial
lookup and the token cost of the catalog disappears from the measurement.

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
