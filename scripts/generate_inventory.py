#!/usr/bin/env python3
"""Generate an Ansible inventory from Terraform JSON output."""

import argparse
import ipaddress
import json
import sys
from pathlib import Path


def output_ip(outputs: dict, name: str) -> str:
    """Return and validate one Terraform IP output."""
    try:
        value = outputs[name]["value"]
        ipaddress.ip_address(value)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"Terraform output {name!r} is missing or invalid") from error
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("generated/inventory.ini"),
        help="inventory destination (default: generated/inventory.ini)",
    )
    args = parser.parse_args()

    try:
        outputs = json.load(sys.stdin)
        app_public_ip = output_ip(outputs, "app_public_ip")
        db_public_ip = output_ip(outputs, "db_public_ip")
        db_private_ip = output_ip(outputs, "db_private_ip")
    except (json.JSONDecodeError, ValueError) as error:
        parser.error(str(error))

    inventory = f"""[app]
app-server ansible_host={app_public_ip}

[db]
db-server ansible_host={db_public_ip}

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
db_host={db_private_ip}
"""

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(inventory, encoding="utf-8")
    print(f"Generated {args.output}")


if __name__ == "__main__":
    main()
