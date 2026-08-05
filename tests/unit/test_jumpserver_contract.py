from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def load_client() -> ModuleType:
    path = Path("ansible/roles/jumpserver_bootstrap/files/jumpserver_reconcile.py")
    spec = importlib.util.spec_from_file_location("jumpserver_reconcile", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_api_contract_is_pinned_to_inspected_release() -> None:
    client = load_client()
    assert client.SUPPORTED_JUMPSERVER == "v4.10.18"
    assert client.ENDPOINTS["permissions"] == "/api/v1/perms/asset-permissions/"
    assert client.ENDPOINTS["command_filters"] == "/api/v1/acls/command-filter-acls/"
    assert client.SYSTEM_USER_ROLE_ID.endswith("0003")
    assert client.ORG_USER_ROLE_ID.endswith("0007")


def test_command_filter_fields_are_narrow() -> None:
    source = Path("ansible/roles/jumpserver_bootstrap/files/jumpserver_reconcile.py").read_text(
        encoding="utf-8"
    )
    for command in ("sudo -i", "sudo su", "sudo su -", "cat /etc/shadow"):
        assert command in source
    assert '"actions": ["connect"]' in source
    assert '"protocols": ["ssh"]' in source


def test_read_representations_match_minimal_write_payloads() -> None:
    client = load_client()
    assert client.matches({"id": "3", "name": "Linux"}, "3")
    assert client.matches({"value": "connect", "label": "Connect"}, "connect")
    assert client.matches(
        [{"name": "ssh", "port": 22, "required": True}],
        [{"name": "ssh", "port": 22}],
    )
    assert client.matches(
        [{"id": "asset-1", "name": "Sensitive"}],
        ["asset-1"],
    )
