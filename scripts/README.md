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
export SSH_KEY="$HOME/.ssh/barq-task1-polah"
bash scripts/deploy.sh
```

Set `ANSIBLE_VAULT_PASSWORD_FILE` before running the script to avoid the Vault
password prompt. Keep that password file outside this repository.

The generated inventory is written to `generated/inventory.ini` and is ignored
by Git. It contains only host addresses and non-secret connection settings.

## Test backup and restoration

The backup/restore test is destructive by design: it restores the complete
application database to the snapshot made during the test. Run it only against
an isolated assignment environment with no concurrent users or important
writes.

After a successful deployment, run:

```sh
export SSH_KEY="$HOME/.ssh/barq-task1-polah"
bash scripts/test_backup_restore.sh
```

The script verifies application health and local database readiness, creates a
unique note through the application host, triggers and validates a backup on
the database host, deletes the note, confirms the deletion, restores the
backup, confirms the note returned, and removes the test record. If the test is
interrupted after deletion, its exit handler attempts to restore the captured
backup before exiting.

For manual inspection after the automated test:

```sh
DB_IP="$(terraform -chdir=terraform output -raw db_public_ip)"

ssh -i "$SSH_KEY" "ubuntu@$DB_IP" \
  'sudo systemctl is-enabled barq-postgres-backup.timer && \
   sudo systemctl is-active barq-postgres-backup.timer && \
   sudo systemctl list-timers barq-postgres-backup.timer && \
   sudo find /srv/barq-postgresql/backups -maxdepth 1 -type f \
     -name "barq-postgres-*.dump" -printf "%M %u:%g %p\n"'
```

Expected results are `enabled`, `active`, a future timer run, and root-owned
backup files with `-rw-------` permissions under the EBS mount.

## Destroy

Save any required backup or test evidence first. Destroying the infrastructure
deletes the EC2 instances and their attached lab EBS volumes:

```sh
terraform -chdir=terraform destroy
```
