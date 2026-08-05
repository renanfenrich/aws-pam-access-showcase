#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan_json", type=Path)
    parser.add_argument("summary", type=Path)
    args = parser.parse_args()
    document: dict[str, Any] = json.loads(args.plan_json.read_text(encoding="utf-8"))
    changes = []
    destructive = []
    for change in document.get("resource_changes", []):
        actions = change["change"]["actions"]
        if actions == ["no-op"]:
            continue
        item = {"address": change["address"], "actions": actions}
        changes.append(item)
        if "delete" in actions:
            destructive.append(item)
    lines = [
        "## Sanitized Terraform plan",
        "",
        "Values are intentionally omitted; only resource addresses and actions are shown.",
        "",
        "| Address | Actions |",
        "| --- | --- |",
        *[f"| `{item['address']}` | `{', '.join(item['actions'])}` |" for item in changes],
        "" if changes else "No resource changes.",
    ]
    if destructive:
        lines.extend(
            ["", f"**Blocked:** {len(destructive)} deletion or replacement operation(s) detected."]
        )
    args.summary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if destructive:
        raise SystemExit(3)


if __name__ == "__main__":
    main()
