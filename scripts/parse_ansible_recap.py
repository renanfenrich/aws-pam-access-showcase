#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

RECAP = re.compile(
    r"^(?P<host>[^ ]+)\s+: .*changed=(?P<changed>\d+).*failed=(?P<failed>\d+)", re.MULTILINE
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    matches = [match.groupdict() for match in RECAP.finditer(args.log.read_text(encoding="utf-8"))]
    if not matches:
        raise SystemExit("No Ansible recap was found")
    changed = sum(int(item["changed"]) for item in matches)
    failed = sum(int(item["failed"]) for item in matches)
    controls = [
        {
            "control": "second-run-no-changes",
            "status": "pass" if changed == 0 else "fail",
            "changed": changed,
        },
        {
            "control": "second-run-no-failures",
            "status": "pass" if failed == 0 else "fail",
            "failed": failed,
        },
    ]
    args.output.write_text(json.dumps({"controls": controls}, indent=2) + "\n", encoding="utf-8")
    if changed or failed:
        raise SystemExit("Ansible idempotence check failed")


if __name__ == "__main__":
    main()
