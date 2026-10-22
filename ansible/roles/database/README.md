# PostgreSQL role

This role deploys the pinned PostgreSQL container on the database EC2 host. It
formats and mounts the single attached non-root EBS disk, binds PostgreSQL only
to the database private IP, initializes a dedicated application user/database,
and verifies container health and application credentials.

## Required variables

The normal configuration comes from `ansible/group_vars/all/app_vars.yml` and
the Terraform-generated inventory:

- `db_host`: database EC2 private IP
- `db_port`: PostgreSQL port
- `db_name`: application database
- `db_user`: non-administrator application user

Create the encrypted Vault file interactively:

```bash
ansible-vault create ansible/group_vars/all/vault.yml
```

Enter two different strong passwords using the variable names shown in
`ansible/group_vars/all/vault.yml.example`:

```yaml
vault_db_admin_password: <strong-administrator-password>
vault_db_password: <strong-application-password>
```

Keep the Vault password outside the repository. The encrypted `vault.yml` file
may be committed, but it must begin with the Ansible Vault header and contain
no plaintext values.

## EBS selection

The role automatically uses the single non-root disk attached to the database
host. If the host has more than one additional disk, set
`postgres_data_device` explicitly in inventory or host variables.

The filesystem module creates the filesystem only when required and never
forces an overwrite. The mount module both mounts the disk and records it in
`/etc/fstab`, so repeated playbook runs preserve existing PostgreSQL data.

Role-specific paths, ports, health-check timings, file modes, and resource
limits are defined in `defaults/main.yml`. A Compose-template change notifies
the restart handler, which recreates the PostgreSQL service once with the new
configuration before the role performs its normal health and login checks.

Before the application is deployed, `playbook.yml` runs the role's
`tasks/readiness.yml` from the application host. This confirms that the app EC2
can reach the PostgreSQL private address and port rather than merely checking
connectivity locally on the database host.

## Run and verify

The common Docker role must run before this role:

```bash
ansible-galaxy collection install -r ansible/requirements.yml

ansible-playbook \
  -i generated/inventory.ini \
  ansible/playbook.yml \
  --ask-vault-pass
```

Run the playbook a second time and confirm the database host reports no
unnecessary changes. Do not use `docker compose down --volumes` during
persistence testing.
