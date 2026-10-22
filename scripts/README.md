# Scripts

Run the deployment workflow from WSL2. It provisions the Terraform resources,
creates the Ansible inventory from Terraform outputs, runs the playbook, and
checks the API health and basic CRUD behavior.

## Prerequisites

- AWS CLI authenticated as the IAM user
- Terraform, Python 3, Ansible, and curl
- `terraform/terraform.tfvars` with `my_ip` and `key_name`
- Encrypted `ansible/group_vars/all/vault.yml`
- The matching AWS SSH private key stored outside this repository

## Deploy

From the repository root:

```sh
export SSH_KEY="$HOME/.ssh/barq-key.pem"
bash scripts/deploy.sh
```

Set `ANSIBLE_VAULT_PASSWORD_FILE` before running the script to avoid the Vault
password prompt. Keep that password file outside this repository.

The generated inventory is written to `generated/inventory.ini` and is ignored
by Git. It contains only host addresses and non-secret connection settings.

## Destroy

Save any required backup or test evidence first. Destroying the infrastructure
deletes the EC2 instances and their attached lab EBS volumes:

```sh
terraform -chdir=terraform destroy
```
