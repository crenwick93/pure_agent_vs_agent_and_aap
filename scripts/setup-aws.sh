#!/usr/bin/env bash
set -euo pipefail

# setup-aws.sh — Prepare AWS environment for the benchmark.
#
# Creates the foundational infrastructure that would already exist in any
# real AWS account: default VPC (restored if deleted), a security group
# allowing SSH from the AAP controller and your current IP.
#
# Run once before testing. Both arms (pure agent and AAP) use this infra.
#
# Usage:
#   ./scripts/setup-aws.sh
#
# Optional environment variables:
#   AWS_REGION          (default: eu-west-1)
#   AAP_CONTROLLER_IP   IP of your AAP controller for SSH access (optional)

REGION="${AWS_REGION:-eu-west-1}"
SG_NAME="benchmark-sandbox-sg"
TAG_KEY="project"
TAG_VALUE="aap-token-bench"

echo "=== Setting up AWS environment in ${REGION} ==="

# --- Ensure default VPC exists ---
VPC_ID=$(aws ec2 describe-vpcs \
  --region "${REGION}" \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text 2>/dev/null || echo "None")

if [[ "${VPC_ID}" == "None" || -z "${VPC_ID}" ]]; then
  echo "No default VPC found — creating one..."
  VPC_ID=$(aws ec2 create-default-vpc \
    --region "${REGION}" \
    --query "Vpc.VpcId" \
    --output text)
  echo "Created default VPC: ${VPC_ID}"
else
  echo "Default VPC exists: ${VPC_ID}"
fi

# --- Get your public IP for SSH access ---
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "Your public IP: ${MY_IP}"

# --- Create or find the security group ---
SG_ID=$(aws ec2 describe-security-groups \
  --region "${REGION}" \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || echo "None")

if [[ "${SG_ID}" == "None" || -z "${SG_ID}" ]]; then
  echo "Creating security group: ${SG_NAME}"
  SG_ID=$(aws ec2 create-security-group \
    --region "${REGION}" \
    --group-name "${SG_NAME}" \
    --description "SSH access for aap-token-bench sandbox instances" \
    --vpc-id "${VPC_ID}" \
    --query "GroupId" \
    --output text)

  aws ec2 create-tags \
    --region "${REGION}" \
    --resources "${SG_ID}" \
    --tags "Key=${TAG_KEY},Value=${TAG_VALUE}"

  echo "Created security group: ${SG_ID}"
else
  echo "Security group exists: ${SG_ID}"
fi

# --- Add SSH rule for your IP ---
aws ec2 authorize-security-group-ingress \
  --region "${REGION}" \
  --group-id "${SG_ID}" \
  --protocol tcp \
  --port 22 \
  --cidr "${MY_IP}/32" \
  2>/dev/null && echo "Added SSH rule for ${MY_IP}/32" \
  || echo "SSH rule for ${MY_IP}/32 already exists"

# --- Add SSH rule for AAP controller (if provided) ---
if [[ -n "${AAP_CONTROLLER_IP:-}" ]]; then
  aws ec2 authorize-security-group-ingress \
    --region "${REGION}" \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr "${AAP_CONTROLLER_IP}/32" \
    2>/dev/null && echo "Added SSH rule for AAP controller ${AAP_CONTROLLER_IP}/32" \
    || echo "SSH rule for AAP controller already exists"
fi

# --- Get a subnet ID for reference ---
SUBNET_ID=$(aws ec2 describe-subnets \
  --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
  --query "Subnets[0].SubnetId" \
  --output text)

echo ""
echo "=== Environment ready ==="
echo "  Region:          ${REGION}"
echo "  VPC:             ${VPC_ID}"
echo "  Security Group:  ${SG_ID} (${SG_NAME})"
echo "  Subnet (first):  ${SUBNET_ID}"
echo ""
echo "Add these to your testing rules if needed:"
echo "  Security group: ${SG_NAME}"
echo "  VPC ID: ${VPC_ID}"
