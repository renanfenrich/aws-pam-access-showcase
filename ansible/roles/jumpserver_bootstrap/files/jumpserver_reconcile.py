#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import boto3
import requests

SUPPORTED_JUMPSERVER = "v4.10.18"
DEFAULT_ORG_ID = "00000000-0000-0000-0000-000000000002"
SYSTEM_USER_ROLE_ID = "00000000-0000-0000-0000-000000000003"
ORG_USER_ROLE_ID = "00000000-0000-0000-0000-000000000007"
ENDPOINTS = {
    "auth": "/api/v1/authentication/auth/",
    "users": "/api/v1/users/users/",
    "nodes": "/api/v1/assets/nodes/",
    "platforms": "/api/v1/assets/platforms/",
    "assets": "/api/v1/assets/hosts/",
    "accounts": "/api/v1/accounts/accounts/",
    "permissions": "/api/v1/perms/asset-permissions/",
    "command_groups": "/api/v1/acls/command-groups/",
    "command_filters": "/api/v1/acls/command-filter-acls/",
}


class API:
    def __init__(self, base_url: str, ca_file: Path, admin_password: str) -> None:
        self.base_url = base_url.rstrip("/") + "/"
        self.session = requests.Session()
        self.session.verify = str(ca_file)
        self.session.headers.update({"User-Agent": f"aws-pam-showcase/{SUPPORTED_JUMPSERVER}"})
        response = self.session.post(
            self.url(ENDPOINTS["auth"]),
            json={"username": "admin", "password": admin_password},
            timeout=30,
        )
        self._ok(response)
        token = response.json().get("token")
        if not token:
            raise RuntimeError("JumpServer administrator authentication returned no bearer token")
        self.session.headers.update(
            {"Authorization": f"Bearer {token}", "X-JMS-ORG": DEFAULT_ORG_ID}
        )

    def url(self, endpoint: str) -> str:
        return urljoin(self.base_url, endpoint.lstrip("/"))

    @staticmethod
    def _ok(response: requests.Response) -> None:
        if response.status_code >= 400:
            detail = response.text[:500].replace("\n", " ")
            raise RuntimeError(f"JumpServer API {response.status_code}: {detail}")

    def schema_paths(self) -> set[str]:
        response = self.session.get(self.url("/api/swagger.json"), timeout=60)
        self._ok(response)
        return {path.rstrip("/") for path in response.json().get("paths", {})}

    def list(self, endpoint: str, **params: str) -> list[dict[str, Any]]:
        response = self.session.get(self.url(endpoint), params=params, timeout=30)
        self._ok(response)
        data = response.json()
        if isinstance(data, dict):
            data = data.get("results", data.get("data", []))
        if not isinstance(data, list):
            raise RuntimeError(f"Unexpected list response for {endpoint}")
        return data

    def post(self, endpoint: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.session.post(self.url(endpoint), json=payload, timeout=30)
        self._ok(response)
        return response.json()

    def patch(self, endpoint: str, object_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.session.patch(self.url(f"{endpoint}{object_id}/"), json=payload, timeout=30)
        self._ok(response)
        return response.json()


def unpack(value: Any) -> Any:
    if isinstance(value, dict):
        if "id" in value:
            return str(value["id"])
        if "value" in value and set(value).issuperset({"value", "label"}):
            return value["value"]
        return {key: unpack(item) for key, item in value.items()}
    if isinstance(value, list):
        return sorted(
            (unpack(item) for item in value), key=lambda item: json.dumps(item, sort_keys=True)
        )
    return value


def matches(current: Any, desired: Any) -> bool:
    """Compare a write payload with JumpServer's richer read representation."""
    if isinstance(desired, dict):
        return isinstance(current, dict) and all(
            key in current and matches(current[key], value) for key, value in desired.items()
        )
    if isinstance(desired, list):
        if not isinstance(current, list) or len(current) != len(desired):
            return False
        unmatched = list(current)
        for wanted in desired:
            match_index = next(
                (index for index, candidate in enumerate(unmatched) if matches(candidate, wanted)),
                None,
            )
            if match_index is None:
                return False
            unmatched.pop(match_index)
        return True
    if isinstance(current, dict):
        if "id" in current:
            return str(current["id"]) == str(desired)
        if "value" in current:
            return matches(current["value"], desired)
    return current == desired or str(current) == str(desired)


def equal_fields(current: dict[str, Any], desired: dict[str, Any]) -> bool:
    return all(matches(current.get(key), value) for key, value in desired.items())


def find(items: list[dict[str, Any]], key: str, value: str) -> dict[str, Any] | None:
    return next((item for item in items if str(item.get(key)) == value), None)


def reconcile(
    api: API,
    endpoint: str,
    lookup_key: str,
    lookup_value: str,
    desired: dict[str, Any],
    *,
    create_only_fields: set[str] | None = None,
    update_write_only_fields: set[str] | None = None,
    mutate: bool = True,
) -> tuple[dict[str, Any], bool]:
    item = find(api.list(endpoint, search=lookup_value), lookup_key, lookup_value)
    if item is None:
        if not mutate:
            raise RuntimeError(f"Required JumpServer object is missing: {lookup_value}")
        return api.post(endpoint, desired), True
    comparable = {
        key: value for key, value in desired.items() if key not in (create_only_fields or set())
    }
    if equal_fields(item, comparable):
        return item, False
    if not mutate:
        return item, True
    patch_payload = dict(comparable)
    for field in update_write_only_fields or set():
        patch_payload[field] = desired[field]
    return api.patch(endpoint, str(item["id"]), patch_payload), True


def get_secret(client: Any, secret_id: str) -> str:
    return str(client.get_secret_value(SecretId=secret_id)["SecretString"])


def required_schema_paths(api: API) -> None:
    paths = api.schema_paths()
    expected = {endpoint.rstrip("/") for key, endpoint in ENDPOINTS.items() if key != "auth"}
    missing = sorted(expected - paths)
    if missing:
        raise RuntimeError(
            f"JumpServer API schema is incompatible with {SUPPORTED_JUMPSERVER}; missing: {missing}"
        )


def execute(args: argparse.Namespace) -> dict[str, Any]:
    names: dict[str, str] = json.loads(args.secret_names)
    secrets_client = boto3.client("secretsmanager", region_name=args.region)
    admin_password = get_secret(secrets_client, names["jumpserver-admin-password"])
    demo_password = get_secret(secrets_client, names["jumpserver-demo-user-password"])
    ssh_key = json.loads(get_secret(secrets_client, names["sensitive-resource-ssh-key"]))
    credential_marker = hashlib.sha256(ssh_key["public_key"].encode()).hexdigest()[:16]
    api = API(args.base_url, args.ca_file, admin_password)
    required_schema_paths(api)
    changed = False

    user_payload = {
        "name": "Portfolio Operator",
        "username": "portfolio-operator",
        "password": demo_password,
        "password_strategy": "custom",
        "mfa_level": 2,
        "is_active": True,
        "system_roles": [SYSTEM_USER_ROLE_ID],
        "org_roles": [ORG_USER_ROLE_ID],
    }
    user, item_changed = reconcile(
        api,
        ENDPOINTS["users"],
        "username",
        "portfolio-operator",
        user_payload,
        create_only_fields={"password", "password_strategy"},
        mutate=not args.verify_only,
    )
    changed |= item_changed

    node_path = "/showcase/private-resources"
    node = next(
        (
            item
            for item in api.list(ENDPOINTS["nodes"], search="private-resources")
            if str(item.get("full_value", "")).endswith(node_path)
        ),
        None,
    )
    if node is None:
        if args.verify_only:
            raise RuntimeError(f"Required JumpServer node is missing: {node_path}")
        node = api.post(ENDPOINTS["nodes"], {"full_value": node_path})
        changed = True

    platforms = api.list(ENDPOINTS["platforms"], name="Linux")
    platform = find(platforms, "name", "Linux") or find(platforms, "name", "Linux host")
    if platform is None:
        raise RuntimeError("Pinned schema is present but no Linux platform exists")
    asset_payload = {
        "name": "sensitive-resource",
        "address": args.asset_address,
        "platform": str(platform["id"]),
        "protocols": [{"name": "ssh", "port": 22}],
        "nodes": [str(node["id"])],
        "is_active": True,
        "comment": "AWS PAM access showcase isolated resource",
    }
    asset, item_changed = reconcile(
        api,
        ENDPOINTS["assets"],
        "name",
        "sensitive-resource",
        asset_payload,
        mutate=not args.verify_only,
    )
    changed |= item_changed

    account_payload = {
        "name": "jms-operator",
        "username": "jms-operator",
        "asset": str(asset["id"]),
        "secret_type": "ssh_key",
        "secret": ssh_key["private_key"],
        "privileged": False,
        "is_active": True,
        "comment": f"automation-key-sha256:{credential_marker}",
        "on_invalid": "update",
    }
    account, item_changed = reconcile(
        api,
        ENDPOINTS["accounts"],
        "username",
        "jms-operator",
        account_payload,
        create_only_fields={"secret", "on_invalid"},
        update_write_only_fields={"secret"},
        mutate=not args.verify_only,
    )
    changed |= item_changed

    start = dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    permission_payload = {
        "name": "portfolio-operator-sensitive-resource-ssh",
        "users": [str(user["id"])],
        "assets": [str(asset["id"])],
        "accounts": ["jms-operator"],
        "protocols": ["ssh"],
        "actions": ["connect"],
        "date_start": start,
        "date_expired": args.expiration,
        "is_active": True,
    }
    permission, item_changed = reconcile(
        api,
        ENDPOINTS["permissions"],
        "name",
        permission_payload["name"],
        permission_payload,
        create_only_fields={"date_start"},
        mutate=not args.verify_only,
    )
    changed |= item_changed

    group_payload = {
        "name": "portfolio-forbidden-commands",
        "type": "command",
        "content": "sudo -i\nsudo su\nsudo su -\ncat /etc/shadow",
        "ignore_case": True,
        "comment": "Non-destructive showcase denial rules",
    }
    command_group, item_changed = reconcile(
        api,
        ENDPOINTS["command_groups"],
        "name",
        group_payload["name"],
        group_payload,
        mutate=not args.verify_only,
    )
    changed |= item_changed

    filter_payload = {
        "name": "portfolio-operator-sensitive-resource-deny",
        "users": {"type": "ids", "ids": [str(user["id"])]},
        "assets": {"type": "ids", "ids": [str(asset["id"])]},
        "accounts": ["jms-operator"],
        "command_groups": [str(command_group["id"])],
        "action": "reject",
        "priority": 10,
        "is_active": True,
        "org_id": DEFAULT_ORG_ID,
    }
    command_filter, item_changed = reconcile(
        api,
        ENDPOINTS["command_filters"],
        "name",
        filter_payload["name"],
        filter_payload,
        mutate=not args.verify_only,
    )
    changed |= item_changed

    matching_assets = [
        item
        for item in api.list(ENDPOINTS["assets"], search="sensitive-resource")
        if item.get("name") == "sensitive-resource"
    ]
    matching_users = [
        item
        for item in api.list(ENDPOINTS["users"], search="portfolio-operator")
        if item.get("username") == "portfolio-operator"
    ]
    matching_accounts = [
        item
        for item in api.list(ENDPOINTS["accounts"], search="jms-operator")
        if item.get("username") == "jms-operator" and matches(item.get("asset"), str(asset["id"]))
    ]
    exact_authorization = (
        matches(permission.get("users"), [str(user["id"])])
        and matches(permission.get("assets"), [str(asset["id"])])
        and matches(permission.get("accounts"), ["jms-operator"])
        and matches(permission.get("protocols"), ["ssh"])
        and matches(permission.get("actions"), ["connect"])
    )
    exact_filter_scope = (
        matches(command_filter.get("users"), filter_payload["users"])
        and matches(command_filter.get("assets"), filter_payload["assets"])
        and matches(command_filter.get("accounts"), ["jms-operator"])
        and matches(command_filter.get("command_groups"), [str(command_group["id"])])
    )
    command_filter_action = unpack(command_filter.get("action"))
    controls = [
        {"control": "schema-compatible", "status": "pass", "expected": SUPPORTED_JUMPSERVER},
        {
            "control": "one-user",
            "status": "pass" if len(matching_users) == 1 else "fail",
        },
        {"control": "one-asset", "status": "pass" if len(matching_assets) == 1 else "fail"},
        {
            "control": "managed-account",
            "status": "pass" if len(matching_accounts) == 1 else "fail",
        },
        {
            "control": "one-user-account-asset-ssh-connect-only",
            "status": "pass" if exact_authorization else "fail",
        },
        {
            "control": "transfer-and-session-sharing-denied",
            "status": "pass" if matches(permission.get("actions"), ["connect"]) else "fail",
        },
        {
            "control": "authorization-expires",
            "status": "pass" if str(permission.get("date_expired")) == args.expiration else "fail",
        },
        {
            "control": "command-filter",
            "status": "pass"
            if command_filter_action == "reject" and exact_filter_scope
            else "fail",
        },
    ]
    if any(item["status"] != "pass" for item in controls):
        raise RuntimeError("JumpServer policy verification failed")
    return {"version": SUPPORTED_JUMPSERVER, "changed": changed, "controls": controls}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--ca-file", type=Path, required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--secret-names", required=True)
    parser.add_argument("--asset-address", required=True)
    parser.add_argument("--expiration", required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    result = execute(args)
    if args.verify_only and result["changed"]:
        raise RuntimeError("JumpServer policy drift was found during verification")
    print(json.dumps(result, separators=(",", ":"), sort_keys=True))


if __name__ == "__main__":
    main()
