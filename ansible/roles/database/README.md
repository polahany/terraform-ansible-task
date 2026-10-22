# PostgreSQL role

This role deploys the pinned PostgreSQL container on the database EC2 host. It
formats and mounts the single attached non-root EBS disk, binds PostgreSQL only
to the database private IP, initializes a dedicated application user/database,
verifies container health and application credentials, and configures daily
database backups with retention.

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

## Backup and restore

The role installs a persistent systemd timer named
`barq-postgres-backup.timer`. It runs once per day at 02:00 UTC, with up to ten
minutes of randomized delay. `Persistent=true` causes a missed run to execute
after the database host next starts.

Backups are compressed PostgreSQL custom archives stored in
`/srv/barq-postgresql/backups`. This is on the attached EBS filesystem and is a
sibling of the bind-mounted database data directory, so the archives do not
depend on the container writable layer. Files are created atomically with mode
`0600`, validated with `pg_restore --list`, and deleted after seven days by
default. The retention period and schedule are configurable in
`defaults/main.yml`.

Both scripts wait for PostgreSQL readiness through the local container socket.
The Ansible playbook separately checks the database private address from the
application host before deploying the application, covering readiness across
the two-host boundary.

Create and validate a backup manually:

```bash
sudo /usr/local/sbin/barq-postgres-backup
sudo systemctl status barq-postgres-backup.timer
sudo systemctl list-timers barq-postgres-backup.timer
```

Restore an archive only during a maintenance or isolated test window because
the operation replaces the whole application database:

```bash
sudo /usr/local/sbin/barq-postgres-restore \
  /srv/barq-postgresql/backups/barq-postgres-YYYYMMDDTHHMMSS.NNNNNNNNNZ.dump
```

Before changing the database, the restore script validates the selected
archive and creates a timestamped `pre-restore` safety backup. Backup and
restore share a file lock so they cannot run concurrently.

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

The repository-level destructive workflow test creates a note, backs up the
database, deletes the note, restores the archive, verifies the note through the
application host, and removes the test note:

```bash
export SSH_KEY="$HOME/.ssh/barq-task1-polah"
bash scripts/test_backup_restore.sh
```

Run this test only against an isolated assignment environment. Writes made
after the test backup are intentionally rolled back by the full-database
restore.
