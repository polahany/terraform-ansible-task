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
|-- ansible/README.md     Ansible placeholder
|-- terraform/README.md   Terraform placeholder
|-- scripts/README.md     Deployment scripts placeholder
|-- docs/team-contract.md Agreed infrastructure and deployment contract
|-- compose.yaml          Local application and PostgreSQL stack
|-- .gitignore            Generated-file and secret exclusions
`-- README.md
```

Only the application is implemented. The Terraform, Ansible, and deployment
script folders are intentionally placeholders.

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

The repository contains example values only. Real `.env` files, private keys,
Terraform state, Vault password files, generated inventories, and backups are
ignored and must never be committed.
