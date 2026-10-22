# Notes API - BARQ assignment

A small Flask and PostgreSQL Notes API prepared for deployment with Terraform,
Ansible, Docker, and Nginx.

## Repository structure

```text
.
|-- app/
|   |-- src/              Flask application and database schema
|   |-- tests/            Unit tests
|   |-- Dockerfile        Production application image
|   `-- README.md         Application usage and API documentation
|-- ansible/              Two-host application and database deployment
|-- terraform/            AWS networking, EC2, and EBS infrastructure
|-- scripts/              Deployment and backup/restore workflow tests
|-- docs/team-contract.md Agreed infrastructure and deployment contract
|-- compose.yaml          Local application and PostgreSQL stack
|-- .gitignore            Generated-file and secret exclusions
`-- README.md
```

Terraform provisions the AWS infrastructure. Ansible deploys Docker Engine,
PostgreSQL, the Flask application, Nginx, and the scheduled backup/restore
workflow across the two EC2 instances.

## Architecture

```text
Internet -> Nginx:80 -> app:8080 -> DB_PRIVATE_IP:5432 -> PostgreSQL
```

Only Nginx will be publicly exposed in AWS. PostgreSQL will accept traffic only
from the application instance.

## Run locally

```powershell
docker compose up --build
```

Open `http://127.0.0.1:8000`. Local ports bind only to `127.0.0.1`. See
[app/README.md](app/README.md) for API examples and tests.

## Test the Terraform and Ansible workflow from WSL2

### Prerequisites

- Terraform, Ansible, and the AWS CLI are installed in WSL2.
- The AWS CLI is authenticated with an IAM user or role, not the root user.
- `terraform/terraform.tfvars` contains the AWS region, project name, current
  public IP CIDR, instance type, AMI ID, and the name of an existing AWS key
  pair. This file is ignored by Git.
- The private half of that AWS key pair is available only on the local machine.

From the repository root, select the AWS profile and confirm its identity:

```bash
cd "/mnt/d/programming/barq intern/barq-intern-assignment-1"

# Renew the temporary login first if the barq-lab session has expired:
# aws login --profile barq-lab --region us-east-1

export AWS_PROFILE=barq-terraform
export AWS_REGION=us-east-1
export SSH_KEY="$HOME/.ssh/barq-task1-polah"

aws sts get-caller-identity
test -f "$SSH_KEY"
```

Install the required Ansible collection and initialize Terraform:

```bash
ansible-galaxy collection install -r ansible/requirements.yml

terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

Use the current public IPv4 address for the SSH security-group rule, then
create and review a saved Terraform plan:

```bash
MY_IP="$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '\r\n')"

terraform -chdir=terraform plan \
  -input=false \
  -var="my_ip=${MY_IP}/32" \
  -out=deploy.tfplan

terraform -chdir=terraform show deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan
```

Confirm that applying the same Terraform configuration again would make no
changes:

```bash
terraform -chdir=terraform plan \
  -input=false \
  -detailed-exitcode \
  -var="my_ip=${MY_IP}/32"

TF_EXIT=$?
echo "Terraform detailed exit code: $TF_EXIT"
test "$TF_EXIT" -eq 0
```

Exit code `0` means the infrastructure is unchanged, `2` means Terraform found
changes, and `1` means the plan failed.

Read the Terraform outputs and wait for both Ubuntu instances to finish
starting:

```bash
APP_IP="$(terraform -chdir=terraform output -raw app_public_ip)"
DB_IP="$(terraform -chdir=terraform output -raw db_public_ip)"
DB_PRIVATE_IP="$(terraform -chdir=terraform output -raw db_private_ip)"

printf 'App public IP: %s\nDB public IP: %s\nDB private IP: %s\n' \
  "$APP_IP" "$DB_IP" "$DB_PRIVATE_IP"

for HOST in "$APP_IP" "$DB_IP"; do
  ssh-keygen -R "$HOST" >/dev/null 2>&1 || true

  until ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -i "$SSH_KEY" \
    "ubuntu@$HOST" true
  do
    echo "Waiting for SSH on $HOST..."
    sleep 10
  done

  ssh -i "$SSH_KEY" "ubuntu@$HOST" "sudo cloud-init status --wait"
done
```

Generate the ignored Ansible inventory from the Terraform outputs:

```bash
mkdir -p ansible/inventories

cat > ansible/inventories/generated.ini <<EOF
[app]
app-server ansible_host=${APP_IP}

[db]
db-server ansible_host=${DB_IP}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${SSH_KEY}
ansible_python_interpreter=/usr/bin/python3
EOF
```

Explicitly select `ansible.cfg` because Ansible may ignore configuration files
inside a world-writable Windows-mounted directory:

```bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
INVENTORY="$PWD/ansible/inventories/generated.ini"

ansible-inventory -i "$INVENTORY" --graph
ansible all -i "$INVENTORY" -m ping
ansible-playbook -i "$INVENTORY" ansible/playbook.yml --diff
```

Verify Docker on both instances:

```bash
ansible all -i "$INVENTORY" --become -m command -a "docker --version"
ansible all -i "$INVENTORY" --become -m command -a "docker compose version"
ansible all -i "$INVENTORY" --become -m command -a "systemctl is-active docker"
```

Ad-hoc `command` checks are displayed as `CHANGED` because Ansible cannot infer
whether an arbitrary command modifies the host. Successful return codes and an
`active` Docker service confirm the checks passed.

Run the playbook a second time to test idempotency:

```bash
ansible-playbook -i "$INVENTORY" ansible/playbook.yml --diff
```

The second playbook recap should report `changed=0` and `failed=0` for both
hosts.

### Destroy the AWS infrastructure after testing

Create and review a saved destruction plan:

```bash
terraform -chdir=terraform plan \
  -destroy \
  -input=false \
  -out=destroy.tfplan

terraform -chdir=terraform show destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
```

Confirm that Terraform has no remaining managed resources:

```bash
terraform -chdir=terraform state list
```

This command should produce no output. Do not delete the Terraform state before
the destroy operation succeeds. The local SSH key and AWS key-pair registration
can be retained for later test runs and do not incur an AWS charge.

The repository contains example values only. Real `.env` files, private keys,
Terraform state, Vault password files, generated inventories, and backups are
ignored and must never be committed.
