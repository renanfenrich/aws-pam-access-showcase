from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any


def terraform_output(terraform_dir: Path) -> dict[str, Any]:
    result = subprocess.run(
        ["terraform", f"-chdir={terraform_dir}", "output", "-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    raw: dict[str, Any] = json.loads(result.stdout)
    return {key: item["value"] for key, item in raw.items()}
