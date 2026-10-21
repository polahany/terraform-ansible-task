# Team Contract

## AWS

- Each teammate uses a separate IAM user.
- Use one AWS account in `us-east-1`.
- Protect the root user and IAM users with MFA.
- Use Ubuntu Server 24.04 LTS ARM64 on both EC2 instances.
- AMI: `ami-0e1ab5c876cc030e8` (Ubuntu 24.04 LTS ARM64, `us-east-1`).
- SSH user: `ubuntu`.
- Application server: `t4g.micro` with 8 GiB gp3 EBS.
- Database server: `t4g.micro` with 8 GiB gp3 EBS.
- Destroy the resources after testing to avoid unnecessary charges.

`t4g.micro` is the lowest-cost practical option for this project. Its 1 GiB of
memory is enough for this small workload, while `t4g.nano` has only 512 MiB and
may fail during Docker builds or PostgreSQL operation.

## Application

- Use the Notes API.
- Required endpoints: `GET /health`, `POST /notes`, and `GET /notes`.
- The app listens on port `8080` inside its container.
- Nginx listens on port `80` and proxies to `http://app:8080`.
- PostgreSQL listens on port `5432` on the database instance's private IP.

## Docker

- Service names: `nginx`, `app`, and `postgres`.
- The app server network is named `frontend` and contains `nginx` and `app`.
- Use these versioned images:
  - `nginx:1.28.0-alpine`
  - `postgres:17.6-alpine`
  - `python:3.14.6-slim-bookworm`
  - `barq-notes:1.0.0`
- Ansible copies the app source to the app server and builds the app image there.
- No manual Docker commands are required during deployment.

## Terraform

Terraform outputs must be named exactly:

- `app_public_ip`
- `db_public_ip`
- `db_private_ip`

## Ansible

- Inventory groups: `[app]` and `[db]`.
- Use each instance's public IP for SSH.
- Use `ubuntu` as the SSH user.
- Required app variables:

```yaml
app_port: 8080
db_host: <Terraform db_private_ip>
db_port: 5432
db_name: notes
db_user: notes_app
db_password: "{{ vault_db_password }}"
app_image: barq-notes:1.0.0
```

`db_host` must be generated automatically from Terraform output. It must not be
hard-coded.

## Secrets and generated files

- Store the database password in encrypted `ansible/group_vars/all/vault.yml`.
- Keep the Vault password and SSH private key outside the repository.
- Do not commit secrets, Terraform state, generated inventory, or backups.
- `scripts/generate_inventory.py` creates the Ansible inventory from
  `terraform output -json`.
- `scripts/deploy.sh` runs the complete deployment.
- `scripts/destroy.sh` removes the AWS resources.

## Data flow

```text
Internet -> Nginx:80 -> app:8080 -> DB_PRIVATE_IP:5432 -> PostgreSQL
```

The task is complete when deployment is automated, only Nginx is public, the
database accepts traffic only from the app server, data survives container
recreation, backup and restore work, Ansible is idempotent, and Terraform can
destroy all resources.
