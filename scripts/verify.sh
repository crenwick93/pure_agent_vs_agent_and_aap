#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify.sh — the only definition of "delivered"
# ---------------------------------------------------------------------------
# Runs after BOTH arms (pure agent and AAP agent) and knows nothing about
# how the state was reached. Exit 0 means the sandbox meets all six
# conditions. Each check is independent — you'll see PASS/FAIL for each.
#
# The six conditions:
#   1. RHEL 9 instance with at least 8 GB RAM
#   2. PostgreSQL 16 installed, enabled and running
#   3. Security group allows only SSH (22) and Postgres (5432) from dev CIDR
#   4. Tagged team=payments and ttl_days=7
#   5. Registered in the CMDB (stub: checks /tmp/cmdb.json for instance ID)
#   6. SSH hardened: password auth disabled, root login disabled
#
# STUBS:
#   - Check 5 (CMDB) looks for the instance ID in a local JSON file. In
#     production this would query a real CMDB API. The file is written by the
#     provision playbook (or by the pure agent, which has to figure out how).
#
# Usage:
#   ./scripts/verify.sh <instance-id>

set -uo pipefail

REGION="${AWS_REGION:-eu-west-1}"
CMDB="${CMDB_PATH:-/tmp/cmdb.json}"
DEV_CIDR="${DEV_CIDR:-10.0.0.0/8}"
ID="${1:?usage: verify.sh <instance-id>}"
fail=0
check(){ if [ "$1" -eq 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fail=1; fi; }

json=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ID" \
       --query 'Reservations[0].Instances[0]' --output json) || exit 1

# 1. RHEL 9 with at least 8 GB
echo "$json" | grep -qi 'RHEL[_-]\?9' ; check $? "rhel9"
itype=$(echo "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["InstanceType"])')
mem=$(aws ec2 describe-instance-types --region "$REGION" --instance-types "$itype" \
      --query 'InstanceTypes[0].MemoryInfo.SizeInMiB' --output text)
[ "$mem" -ge 8192 ] ; check $? "memory>=8GB ($mem MiB)"

ip=$(echo "$json" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("PrivateIpAddress") or "")')
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$ip"

# 2. Postgres 16 running
$SSH "systemctl is-active --quiet postgresql && psql --version | grep -q ' 16'" 2>/dev/null
check $? "postgres16-running"

# 3. Ingress limited to ssh + postgres from the dev CIDR
sgid=$(echo "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["SecurityGroups"][0]["GroupId"])')
aws ec2 describe-security-groups --region "$REGION" --group-ids "$sgid" \
  --query 'SecurityGroups[0].IpPermissions' --output json \
  | python3 -c "
import json,sys
perms=json.load(sys.stdin)
ports={p.get('FromPort') for p in perms}
cidrs={r['CidrIp'] for p in perms for r in p.get('IpRanges',[])}
sys.exit(0 if ports<={22,5432} and cidrs<={'$DEV_CIDR'} else 1)"
check $? "ingress-restricted"

# 4. Tags
echo "$json" | python3 -c "
import json,sys
t={x['Key']:x['Value'] for x in json.load(sys.stdin).get('Tags',[])}
sys.exit(0 if t.get('team')=='payments' and t.get('ttl_days')=='7' else 1)"
check $? "tags"

# 5. CMDB entry (stub — checks local JSON file, see header comments)
[ -f "$CMDB" ] && grep -q "$ID" "$CMDB" ; check $? "cmdb-registered"

# 6. SSH hardened
$SSH "sudo grep -qE '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config && \
      sudo grep -qE '^\s*PermitRootLogin\s+no' /etc/ssh/sshd_config" 2>/dev/null
check $? "ssh-hardened"

exit $fail
