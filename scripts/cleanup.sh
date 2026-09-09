#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cleanup.sh — teardown everything the benchmark created
# ---------------------------------------------------------------------------
# Finds all EC2 instances tagged benchmark=aap-token-bench and terminates
# them. Also removes their security groups, cancels any EventBridge
# scheduled teardowns, and clears the CMDB stub file.
#
# IMPORTANT: Run this after every test, even if it failed. A forgotten
# instance is the only thing in this demo that costs real money.
#
# Usage:
#   ./scripts/cleanup.sh              # terminate all tagged instances
#   ./scripts/cleanup.sh --sweep 60   # only those older than 60 minutes

set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
TAG_KEY="${TAG_KEY:-benchmark}"
TAG_VALUE="${TAG_VALUE:-aap-token-bench}"
CMDB="${CMDB_PATH:-/tmp/cmdb.json}"
SWEEP_MINUTES=""

[ "${1:-}" = "--sweep" ] && SWEEP_MINUTES="${2:-60}"

ids=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,LaunchTime]' --output text || true)

to_kill=""
while read -r id launched; do
  [ -z "${id:-}" ] && continue
  if [ -n "$SWEEP_MINUTES" ]; then
    age=$(( ( $(date -u +%s) - $(date -u -d "$launched" +%s) ) / 60 ))
    [ "$age" -lt "$SWEEP_MINUTES" ] && continue
  fi
  to_kill="$to_kill $id"
done <<< "$ids"

if [ -n "${to_kill// /}" ]; then
  echo "terminating:$to_kill"
  aws ec2 terminate-instances --region "$REGION" --instance-ids $to_kill >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $to_kill
else
  echo "no tagged instances to terminate"
fi

# Security groups can only go once their instances are gone.
for sg in $(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" \
      --query 'SecurityGroups[].GroupId' --output text || true); do
  aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null \
    && echo "deleted $sg" || echo "could not delete $sg yet"
done

# Clear the CMDB stub (local JSON file — see playbook comments for details).
[ -f "$CMDB" ] && rm -f "$CMDB" && echo "cleared $CMDB"
echo "cleanup done"
