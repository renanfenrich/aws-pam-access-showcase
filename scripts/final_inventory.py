#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from scripts import _terraform as terraform_helper
except ModuleNotFoundError:
    import _terraform as terraform_helper  # type: ignore[no-redef]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terraform-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    deployment = terraform_helper.terraform_output(args.terraform_dir)["deployment"]
    document = {
        "deployment_id": deployment["deployment_id"],
        "region": deployment["region"],
        "managed_nodes": ["openvpn", "jumpserver", "sensitive-resource"],
        "public_nodes": ["openvpn"],
        "private_nodes": ["jumpserver", "sensitive-resource"],
        "secret_containers": sorted(deployment["secret_names"]),
        "contains_secret_values": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
