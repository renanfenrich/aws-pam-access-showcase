#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def result_counts(document: dict[str, Any]) -> tuple[int, int]:
    controls = document.get("controls", [])
    return sum(item.get("status") == "pass" for item in controls), sum(
        item.get("status") != "pass" for item in controls
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", type=Path)
    args = parser.parse_args()
    rows: list[tuple[str, int, int]] = []
    for evidence_file in sorted(args.evidence_dir.glob("*.json")):
        document = json.loads(evidence_file.read_text(encoding="utf-8"))
        passed, failed = result_counts(document)
        rows.append((evidence_file.name, passed, failed))
    lines = [
        "# Sanitized deployment evidence",
        "",
        "| File | Passed | Failed |",
        "| --- | ---: | ---: |",
        *[f"| `{name}` | {passed} | {failed} |" for name, passed, failed in rows],
        "",
        "This bundle excludes credentials, private keys, VPN profiles, Terraform state, "
        "and raw session recordings.",
    ]
    (args.evidence_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
