# Deployment scripts

The root [README](../README.md) is the canonical deployment guide.

- `deploy.sh` provisions Terraform, generates the Ansible inventory, waits for
  cloud-init, runs the playbook, and performs API smoke tests.
- `generate_inventory.py` converts Terraform JSON outputs into the ignored
  `generated/inventory.ini` file.
- `destroy.sh` creates and displays a Terraform destroy plan, then requires two
  explicit confirmations before applying it.

Run from the repository root with `SSH_KEY` set and an encrypted Ansible Vault
file available. Back up PostgreSQL before running `destroy.sh`.
