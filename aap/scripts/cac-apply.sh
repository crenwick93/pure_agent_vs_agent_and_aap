#!/usr/bin/env bash
set -euo pipefail

# Apply AAP Controller objects for the Developer Self-Service catalog.
# Sources the repo-root .env for AAP and AWS credentials.
#
# Usage:
#   ./aap/scripts/cac-apply.sh
#
# Prerequisites:
#   ansible-galaxy collection install -r aap/cac/requirements.yml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PLAYBOOK="${REPO_ROOT}/aap/cac/apply.yml"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  echo "Loading environment from ${REPO_ROOT}/.env"
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

ansible-playbook "${PLAYBOOK}" "$@"
