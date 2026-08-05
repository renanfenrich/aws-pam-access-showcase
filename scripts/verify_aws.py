#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any, cast

import boto3

try:
    from scripts import _terraform as terraform_helper
except ModuleNotFoundError:
    import _terraform as terraform_helper  # type: ignore[no-redef]


def control(name: str, passed: bool, evidence: Any) -> dict[str, Any]:
    return {"control": name, "status": "pass" if passed else "fail", "evidence": evidence}


def instance_by_id(ec2: Any, instance_id: str) -> dict[str, Any]:
    reservations = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"]
    return cast(dict[str, Any], reservations[0]["Instances"][0])


def run_ssm(ssm: Any, instance_id: str, command: str) -> dict[str, Any]:
    command_id = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [command]},
        TimeoutSeconds=60,
    )["Command"]["CommandId"]
    for _ in range(60):
        try:
            result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        except ssm.exceptions.InvocationDoesNotExist:
            time.sleep(2)
            continue
        if result["Status"] in {"Success", "Failed", "TimedOut", "Cancelled"}:
            return cast(dict[str, Any], result)
        time.sleep(2)
    raise TimeoutError(f"SSM command {command_id} did not finish")


def write(path: Path, document: dict[str, Any]) -> None:
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terraform-dir", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--region", required=True)
    args = parser.parse_args()
    deployment = terraform_helper.terraform_output(args.terraform_dir)["deployment"]
    args.evidence_dir.mkdir(parents=True, exist_ok=True)
    ec2 = boto3.client("ec2", region_name=args.region)
    ssm = boto3.client("ssm", region_name=args.region)
    role_ids = {
        "openvpn": deployment["openvpn_instance_id"],
        "jumpserver": deployment["jumpserver_instance_id"],
        "sensitive-resource": deployment["sensitive_instance_id"],
    }
    instances = {role: instance_by_id(ec2, instance_id) for role, instance_id in role_ids.items()}
    controls: list[dict[str, Any]] = []

    for role in ("jumpserver", "sensitive-resource"):
        controls.append(
            control(
                f"{role}-no-public-ip", not instances[role].get("PublicIpAddress"), {"role": role}
            )
        )
    controls.append(
        control(
            "sensitive-subnet-no-default-route",
            not any(
                route.get("DestinationCidrBlock") == "0.0.0.0/0"
                for route in ec2.describe_route_tables(
                    RouteTableIds=[deployment["isolated_route_table_id"]]
                )["RouteTables"][0]["Routes"]
            ),
            {"route_table_class": "isolated", "expected_default_route": False},
        )
    )

    security_groups = {
        role: ec2.describe_security_groups(GroupIds=[group_id])["SecurityGroups"][0]
        for role, group_id in deployment["security_group_ids"].items()
    }
    sensitive_ingress = security_groups["sensitive_resource"]["IpPermissions"]
    ssh_permissions = [
        item
        for item in sensitive_ingress
        if item.get("FromPort") == 22 and item.get("ToPort") == 22
    ]
    jump_group = deployment["security_group_ids"]["jumpserver"]
    target_sg_ok = (
        len(ssh_permissions) == 1
        and ssh_permissions[0].get("IpRanges", []) == []
        and [pair["GroupId"] for pair in ssh_permissions[0].get("UserIdGroupPairs", [])]
        == [jump_group]
    )
    controls.append(
        control(
            "sensitive-ssh-only-from-jumpserver-sg",
            target_sg_ok,
            {"source": "jumpserver-security-group", "port": 22},
        )
    )

    vpn_permissions = security_groups["openvpn"]["IpPermissions"]
    vpn_ok = (
        len(vpn_permissions) == 1
        and vpn_permissions[0].get("IpProtocol") == "udp"
        and vpn_permissions[0].get("FromPort") == 1194
        and [item["CidrIp"] for item in vpn_permissions[0].get("IpRanges", [])]
        == [deployment["operator_cidr"]]
    )
    controls.append(
        control(
            "openvpn-ingress-narrow",
            vpn_ok,
            {"protocol": "udp", "port": 1194, "source": "explicit-operator-cidr"},
        )
    )

    jump_public = any(
        item.get("CidrIp") == "0.0.0.0/0"
        for permission in security_groups["jumpserver"]["IpPermissions"]
        for item in permission.get("IpRanges", [])
    )
    controls.append(
        control(
            "jumpserver-not-public", not jump_public, {"ports": [443, 2222], "public_source": False}
        )
    )

    volume_ids: list[str] = []
    for role, instance in instances.items():
        controls.append(
            control(
                f"{role}-imdsv2",
                instance["MetadataOptions"]["HttpTokens"] == "required",
                {"role": role, "http_tokens": instance["MetadataOptions"]["HttpTokens"]},
            )
        )
        controls.append(
            control(
                f"{role}-no-key-pair",
                not instance.get("KeyName"),
                {"role": role, "key_pair": False},
            )
        )
        volume_ids.extend(
            mapping["Ebs"]["VolumeId"]
            for mapping in instance["BlockDeviceMappings"]
            if "Ebs" in mapping
        )
    volumes = ec2.describe_volumes(VolumeIds=volume_ids)["Volumes"]
    controls.append(
        control(
            "all-ebs-encrypted",
            all(volume["Encrypted"] for volume in volumes),
            {"checked_volumes": len(volumes)},
        )
    )

    managed = {
        item["InstanceId"]: item["PingStatus"]
        for item in ssm.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": list(role_ids.values())}]
        )["InstanceInformationList"]
    }
    controls.append(
        control(
            "all-instances-online-in-ssm",
            all(managed.get(instance_id) == "Online" for instance_id in role_ids.values()),
            {
                "nodes": {
                    role: managed.get(instance_id, "missing")
                    for role, instance_id in role_ids.items()
                }
            },
        )
    )

    probes: list[dict[str, Any]] = []
    for source, expected in (("openvpn", False), ("jumpserver", True)):
        result = run_ssm(
            ssm,
            role_ids[source],
            f"timeout 5 bash -c '</dev/tcp/{deployment['sensitive_private_ip']}/22'",
        )
        reachable = result["ResponseCode"] == 0
        probe = {
            "source": source,
            "destination": "sensitive-resource",
            "port": 22,
            "expected_reachable": expected,
            "observed_reachable": reachable,
            "status": "pass" if reachable == expected else "fail",
        }
        probes.append(probe)
    write(args.evidence_dir / "network-paths.json", {"controls": probes})

    health_command = (
        "curl --fail --silent --show-error --cacert /etc/jumpserver/tls/ca.crt "
        f"https://{deployment['jumpserver_private_ip']}/api/v1/health/ >/dev/null"
    )
    health = run_ssm(
        ssm,
        role_ids["jumpserver"],
        health_command,
    )
    controls.append(
        control(
            "jumpserver-health",
            health["ResponseCode"] == 0,
            {"endpoint": "private-https", "status_code_expected": 200},
        )
    )
    policy = run_ssm(ssm, role_ids["jumpserver"], "cat /var/lib/aws-pam/jumpserver-policy.json")
    if policy["ResponseCode"] != 0:
        raise RuntimeError("JumpServer policy evidence was not available through Systems Manager")
    policy_document: dict[str, Any] = json.loads(policy["StandardOutputContent"])
    write(args.evidence_dir / "jumpserver-policy.json", policy_document)
    write(args.evidence_dir / "aws-controls.json", {"controls": controls})
    if any(item["status"] != "pass" for item in controls + probes) or any(
        item["status"] != "pass" for item in policy_document["controls"]
    ):
        raise SystemExit("One or more security controls failed")


if __name__ == "__main__":
    main()
