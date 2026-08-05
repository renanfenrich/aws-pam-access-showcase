#!/usr/bin/env python3
from __future__ import annotations

import argparse
import time
from pathlib import Path
from typing import Any

import boto3

try:
    from scripts import _terraform as terraform_helper
except ModuleNotFoundError:
    import _terraform as terraform_helper  # type: ignore[no-redef]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terraform-dir", type=Path, required=True)
    parser.add_argument("--region", required=True)
    args = parser.parse_args()
    deployment = terraform_helper.terraform_output(args.terraform_dir)["deployment"]
    client: Any = boto3.client("ssm", region_name=args.region)
    command_id = client.send_command(
        InstanceIds=[deployment["openvpn_instance_id"]],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": ["sudo /usr/local/sbin/revoke-demo-vpn-client"]},
    )["Command"]["CommandId"]
    for _ in range(60):
        try:
            result = client.get_command_invocation(
                CommandId=command_id, InstanceId=deployment["openvpn_instance_id"]
            )
        except client.exceptions.InvocationDoesNotExist:
            time.sleep(2)
            continue
        if result["Status"] == "Success":
            print("OpenVPN demo client revoked.")
            return
        if result["Status"] in {"Failed", "TimedOut", "Cancelled"}:
            raise SystemExit("OpenVPN client revocation failed through Systems Manager")
        time.sleep(2)
    raise SystemExit("OpenVPN client revocation timed out")


if __name__ == "__main__":
    main()
