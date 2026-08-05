#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ipaddress
import json
from pathlib import Path
from typing import Any

try:
    from scripts import _terraform as terraform_helper
except ModuleNotFoundError:
    import _terraform as terraform_helper  # type: ignore[no-redef]


def scalar(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"))


def build_inventory(deployment: dict[str, Any], secret_names: dict[str, str], region: str) -> str:
    vpn_network = ipaddress.ip_network(deployment["vpn_client_cidr"])
    lines = [
        "---",
        "all:",
        "  vars:",
        "    ansible_connection: amazon.aws.aws_ssm",
        f"    ansible_aws_ssm_region: {scalar(region)}",
        f"    ansible_aws_ssm_bucket_name: {scalar(deployment['ansible_transfer_bucket'])}",
        "    ansible_aws_ssm_s3_addressing_style: virtual",
        "    ansible_python_interpreter: /usr/bin/python3",
        f"    aws_region: {scalar(region)}",
        f"    deployment_id: {scalar(deployment['deployment_id'])}",
        f"    vpn_client_cidr: {scalar(deployment['vpn_client_cidr'])}",
        f"    vpn_client_network: {scalar(str(vpn_network.network_address))}",
        f"    vpn_client_netmask: {scalar(str(vpn_network.netmask))}",
        f"    authorization_expiration: {scalar(deployment['authorization_expiration'])}",
        f"    openvpn_private_ip: {scalar(deployment['openvpn_private_ip'])}",
        f"    openvpn_public_ip: {scalar(deployment['openvpn_public_ip'])}",
        f"    jumpserver_private_ip: {scalar(deployment['jumpserver_private_ip'])}",
        f"    sensitive_private_ip: {scalar(deployment['sensitive_private_ip'])}",
        f"    secret_names: {scalar(secret_names)}",
        f"    log_groups: {scalar(deployment['log_groups'])}",
        "  children:",
    ]
    groups = {
        "openvpn": deployment["openvpn_instance_id"],
        "jumpserver": deployment["jumpserver_instance_id"],
        "sensitive_resource": deployment["sensitive_instance_id"],
    }
    for group, instance_id in groups.items():
        lines.extend(
            [
                f"    {group}:",
                "      hosts:",
                f"        {instance_id}:",
            ]
        )
        if group == "jumpserver":
            volume_id = scalar(deployment["jumpserver_data_volume_id"])
            lines.append(f"          jumpserver_data_volume_id: {volume_id}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terraform-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--region", required=True)
    args = parser.parse_args()

    outputs = terraform_helper.terraform_output(args.terraform_dir)
    deployment = outputs["deployment"]
    inventory = build_inventory(deployment, deployment["secret_names"], args.region)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(inventory, encoding="utf-8")


if __name__ == "__main__":
    main()
