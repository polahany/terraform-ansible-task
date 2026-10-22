#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$ROOT_DIR/generated/inventory.ini}"
BACKUP_SCRIPT=/usr/local/sbin/barq-postgres-backup
RESTORE_SCRIPT=/usr/local/sbin/barq-postgres-restore

: "${SSH_KEY:?Set SSH_KEY to the path of the AWS private key}"

for command in ansible-inventory curl python3 ssh; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$SSH_KEY" ]] || {
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
}

[[ -f "$INVENTORY" ]] || {
  echo "Inventory not found: $INVENTORY" >&2
  exit 1
}

mapfile -t connection_values < <(
  ansible-inventory -i "$INVENTORY" --list |
    python3 -c '
import json
import sys

hostvars = json.load(sys.stdin)["_meta"]["hostvars"]
for host in ("app-server", "db-server"):
    values = hostvars[host]
    print(values["ansible_host"])
    print(values.get("ansible_user", "ubuntu"))
'
)

if (( ${#connection_values[@]} != 4 )); then
  echo "Could not resolve app-server and db-server from $INVENTORY" >&2
  exit 1
fi

APP_IP="${connection_values[0]}"
DB_IP="${connection_values[2]}"
DB_USER="${connection_values[3]}"
API_URL="${API_URL:-http://$APP_IP}"
SSH=(
  ssh
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -i "$SSH_KEY"
  "$DB_USER@$DB_IP"
)

NOTE_ID=""
BACKUP_PATH=""
RETENTION_SENTINEL=""
NEEDS_RESTORE=false

cleanup() {
  local exit_code=$?
  trap - EXIT

  if [[ "$NEEDS_RESTORE" == true && -n "$BACKUP_PATH" ]]; then
    echo "Test interrupted; attempting to restore the captured backup." >&2
    "${SSH[@]}" "sudo '$RESTORE_SCRIPT' '$BACKUP_PATH'" >&2 || true
  fi

  if [[ -n "$NOTE_ID" ]]; then
    curl --silent --show-error \
      -o /dev/null \
      -X DELETE \
      "$API_URL/notes/$NOTE_ID" || true
  fi

  if [[ -n "$RETENTION_SENTINEL" ]]; then
    "${SSH[@]}" "sudo rm -f -- '$RETENTION_SENTINEL'" >&2 || true
  fi

  exit "$exit_code"
}
trap cleanup EXIT

echo "Checking application and database readiness..."
curl --fail --silent --show-error \
  --retry 12 \
  --retry-delay 5 \
  --retry-all-errors \
  "$API_URL/health" >/dev/null
"${SSH[@]}" "sudo docker exec --user postgres postgres pg_isready --quiet"
"${SSH[@]}" \
  "sudo systemctl is-enabled --quiet barq-postgres-backup.timer && \
   sudo systemctl is-active --quiet barq-postgres-backup.timer && \
   test \"\$(findmnt -n -o TARGET -T /srv/barq-postgresql/backups)\" = /srv/barq-postgresql"

test_suffix="$(date --utc +'%Y%m%dT%H%M%SZ')-$$"
test_title="backup-restore-test-$test_suffix"
note_json="$(curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"$test_title\",\"content\":\"restore verification\"}" \
  "$API_URL/notes")"
NOTE_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$note_json")"
echo "Created test note $NOTE_ID."

BACKUP_PATH="$("${SSH[@]}" "sudo '$BACKUP_SCRIPT'")"
case "$BACKUP_PATH" in
  /srv/barq-postgresql/backups/barq-postgres-*.dump) ;;
  *)
    echo "Unexpected backup path: $BACKUP_PATH" >&2
    exit 1
    ;;
esac
echo "Created and validated backup: $BACKUP_PATH"

RETENTION_SENTINEL="/srv/barq-postgresql/backups/barq-postgres-retention-test-${test_suffix}.dump"
"${SSH[@]}" \
  "printf retention-test | sudo tee '$RETENTION_SENTINEL' >/dev/null && \
   sudo touch --date='1970-01-02 UTC' '$RETENTION_SENTINEL'"
"${SSH[@]}" \
  "sudo '$BACKUP_SCRIPT' >/dev/null && sudo test ! -e '$RETENTION_SENTINEL'"
RETENTION_SENTINEL=""
echo "Confirmed expired backup retention and EBS-backed storage."

delete_status="$(curl --silent --show-error \
  -o /dev/null \
  -w '%{http_code}' \
  -X DELETE \
  "$API_URL/notes/$NOTE_ID")"
[[ "$delete_status" == 204 ]] || {
  echo "Expected DELETE to return 204; received $delete_status." >&2
  exit 1
}
NEEDS_RESTORE=true

missing_status="$(curl --silent --show-error \
  -o /dev/null \
  -w '%{http_code}' \
  "$API_URL/notes/$NOTE_ID")"
[[ "$missing_status" == 404 ]] || {
  echo "Expected deleted note to return 404; received $missing_status." >&2
  exit 1
}
echo "Confirmed test note $NOTE_ID is deleted."

"${SSH[@]}" "sudo '$RESTORE_SCRIPT' '$BACKUP_PATH'"
NEEDS_RESTORE=false

restored_json="$(curl --fail --silent --show-error \
  --retry 12 \
  --retry-delay 2 \
  --retry-all-errors \
  "$API_URL/notes/$NOTE_ID")"
python3 -c '
import json
import sys

expected_id = int(sys.argv[1])
expected_title = sys.argv[2]
note = json.load(sys.stdin)
assert note["id"] == expected_id, note
assert note["title"] == expected_title, note
' "$NOTE_ID" "$test_title" <<<"$restored_json"
echo "Confirmed restored note $NOTE_ID is readable through the application host."

cleanup_status="$(curl --silent --show-error \
  -o /dev/null \
  -w '%{http_code}' \
  -X DELETE \
  "$API_URL/notes/$NOTE_ID")"
[[ "$cleanup_status" == 204 ]] || {
  echo "Expected cleanup DELETE to return 204; received $cleanup_status." >&2
  exit 1
}
NOTE_ID=""

trap - EXIT
echo "Backup and restoration workflow passed."
