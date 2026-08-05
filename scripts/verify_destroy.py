#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

import boto3

ALLOWED_PENDING_DELETION = {"kms:key", "secretsmanager:secret"}


def resources(client: Any, deployment_id: str) -> list[dict[str, Any]]:
    paginator = client.get_paginator("get_resources")
    found: list[dict[str, Any]] = []
    for page in paginator.paginate(
        TagFilters=[
            {"Key": "project", "Values": ["aws-pam-access-showcase"]},
            {"Key": "deployment", "Values": [deployment_id]},
        ]
    ):
        found.extend(page["ResourceTagMappingList"])
    return found


def resource_type(arn: str) -> str:
    parts = arn.split(":", 5)
    service = parts[2]
    resource = parts[5].split("/", 1)[0]
    return f"{service}:{resource}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--deployment-id", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    client = boto3.client("resourcegroupstaggingapi", region_name=args.region)
    remaining: list[dict[str, Any]] = []
    for _ in range(20):
        remaining = resources(client, args.deployment_id)
        chargeable = [
            item
            for item in remaining
            if resource_type(item["ResourceARN"]) not in ALLOWED_PENDING_DELETION
        ]
        if not chargeable:
            break
        time.sleep(15)
    types = sorted(resource_type(item["ResourceARN"]) for item in remaining)
    chargeable_types = sorted(item for item in types if item not in ALLOWED_PENDING_DELETION)
    document = {
        "controls": [
            {
                "control": "no-chargeable-project-resources",
                "status": "pass" if not chargeable_types else "fail",
                "remaining_resource_types": chargeable_types,
                "pending-deletion-types": sorted(
                    item for item in types if item in ALLOWED_PENDING_DELETION
                ),
            }
        ]
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    if chargeable_types:
        raise SystemExit("Chargeable tagged resources remain after destroy")


if __name__ == "__main__":
    main()
