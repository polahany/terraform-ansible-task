# Notes API - BARQ assignment

Only the application is implemented. Infrastructure folders are placeholders.

```text
compose.yaml         Local app + PostgreSQL stack
app/                 Flask API, schema, Dockerfile and tests
terraform/           Future AWS infrastructure
ansible/
  inventories/       Future generated inventory
  group_vars/        Future configuration and Vault secrets
  playbooks/         Future deployment playbooks
  roles/
    docker_engine/   Future Docker installation
    application/     Future Nginx and app deployment
    database/        Future PostgreSQL deployment
    database_backup/ Future backup and restore automation
scripts/             Future deployment workflow
```

Target architecture: HTTP -> Nginx container -> app container on EC2 A;
app -> PostgreSQL container on EC2 B through its private IP.
Only Nginx's HTTP port will be published on EC2 A. The Dockerfile's
`EXPOSE 8000` documents the app port; it does not publish it.

For local use, run `docker compose up --build` and open
`http://127.0.0.1:8000`. See [app/README.md](app/README.md) for API examples and
tests. No AWS resources, Nginx configuration, deployment Compose projects,
Terraform or Ansible implementation are included at this stage.
