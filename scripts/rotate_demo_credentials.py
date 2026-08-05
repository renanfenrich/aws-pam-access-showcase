#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import boto3


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--secret-name", required=True)
    parser.add_argument("--region", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="aws-pam-rotate-") as temporary:
        key = Path(temporary) / "id_ed25519"
        subprocess.run(
            [
                "/usr/bin/ssh-keygen",
                "-q",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                "jms-operator",
                "-f",
                str(key),
            ],
            check=True,
        )
        payload = {
            "private_key": key.read_text(encoding="utf-8"),
            "public_key": key.with_suffix(".pub").read_text(encoding="utf-8").strip(),
        }
        client: Any = boto3.client("secretsmanager", region_name=args.region)
        client.put_secret_value(SecretId=args.secret_name, SecretString=json.dumps(payload))
        for item in (key, key.with_suffix(".pub")):
            size = item.stat().st_size
            with item.open("r+b") as handle:
                handle.write(b"\0" * size)
                handle.flush()
                os.fsync(handle.fileno())
    print(json.dumps({"rotated": "sensitive-resource-ssh-key"}))


if __name__ == "__main__":
    main()
