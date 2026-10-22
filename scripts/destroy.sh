#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
PLAN_FILE="$TERRAFORM_DIR/destroy.tfplan"

for command in aws terraform; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

aws sts get-caller-identity >/dev/null
terraform -chdir="$TERRAFORM_DIR" init
terraform -chdir="$TERRAFORM_DIR" validate

echo "This will destroy every resource managed by Terraform in $TERRAFORM_DIR."
read -r -p "Type DESTROY to continue: " confirmation
[[ "$confirmation" == "DESTROY" ]] || { echo "Destroy cancelled."; exit 0; }

terraform -chdir="$TERRAFORM_DIR" plan -destroy -input=false -out="$PLAN_FILE"
terraform -chdir="$TERRAFORM_DIR" show "$PLAN_FILE"
read -r -p "Apply the destroy plan shown above? Type DESTROY again: " confirmation
[[ "$confirmation" == "DESTROY" ]] || {
  rm -f "$PLAN_FILE"
  echo "Destroy cancelled; no resources were changed."
  exit 0
}

terraform -chdir="$TERRAFORM_DIR" apply "$PLAN_FILE"
rm -f "$PLAN_FILE"
echo "Terraform destroy completed."
