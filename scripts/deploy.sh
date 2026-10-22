#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
INVENTORY="$ROOT_DIR/generated/inventory.ini"
PLAYBOOK="$ROOT_DIR/ansible/playbook.yml"
VAULT_FILE="$ROOT_DIR/ansible/group_vars/all/vault.yml"
PLAN_FILE="$TERRAFORM_DIR/deploy.tfplan"

: "${SSH_KEY:?Set SSH_KEY to the path of the AWS private key}"

for command in aws terraform python3 ansible ansible-inventory ansible-playbook curl; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$SSH_KEY" ]] || {
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
}

[[ -f "$VAULT_FILE" ]] || {
  echo "Create the encrypted Vault file first: $VAULT_FILE" >&2
  exit 1
}

aws sts get-caller-identity >/dev/null
terraform -chdir="$TERRAFORM_DIR" init
terraform -chdir="$TERRAFORM_DIR" validate
terraform -chdir="$TERRAFORM_DIR" plan -out="$PLAN_FILE"
terraform -chdir="$TERRAFORM_DIR" apply "$PLAN_FILE"
rm -f "$PLAN_FILE"

terraform -chdir="$TERRAFORM_DIR" output -json |
  python3 "$ROOT_DIR/scripts/generate_inventory.py" --output "$INVENTORY"

ansible-inventory -i "$INVENTORY" --list >/dev/null

ANSIBLE_ARGS=(-i "$INVENTORY" --private-key "$SSH_KEY")
ansible all "${ANSIBLE_ARGS[@]}" -m wait_for_connection -a "timeout=300"
ansible all "${ANSIBLE_ARGS[@]}" --become \
  -m command -a "cloud-init status --wait"

if [[ -f "$ROOT_DIR/ansible/requirements.yml" ]]; then
  ansible-galaxy collection install -r "$ROOT_DIR/ansible/requirements.yml"
fi

VAULT_ARGS=()
if [[ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]]; then
  VAULT_ARGS+=(--ask-vault-pass)
fi

ansible-playbook "${ANSIBLE_ARGS[@]}" "${VAULT_ARGS[@]}" "$PLAYBOOK"

APP_IP="$(terraform -chdir="$TERRAFORM_DIR" output -raw app_public_ip)"
API_URL="http://$APP_IP"
curl --fail --retry 12 --retry-delay 5 --retry-all-errors "$API_URL/health"

NOTE="$(curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  -d '{"title":"deployment-smoke-test","content":"created by deploy.sh"}' \
  "$API_URL/notes")"
NOTE_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$NOTE")"
curl --fail --silent --show-error "$API_URL/notes/$NOTE_ID" >/dev/null
curl --fail --silent --show-error -X DELETE "$API_URL/notes/$NOTE_ID"

echo
echo "Deployment succeeded: $API_URL"
