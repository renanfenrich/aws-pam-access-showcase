from __future__ import annotations

import json

from scripts.build_inventory import build_inventory


def test_inventory_contains_only_instance_ids_and_secret_names() -> None:
    deployment = {
        "deployment_id": "test",
        "vpn_client_cidr": "10.250.0.0/24",
        "authorization_expiration": "2099-01-01T00:00:00Z",
        "openvpn_private_ip": "10.42.0.10",
        "openvpn_public_ip": "198.51.100.10",
        "jumpserver_private_ip": "10.42.10.10",
        "sensitive_private_ip": "10.42.20.10",
        "ansible_transfer_bucket": "transfer-bucket",
        "openvpn_instance_id": "i-openvpn",
        "jumpserver_instance_id": "i-jumpserver",
        "sensitive_instance_id": "i-sensitive",
        "jumpserver_data_volume_id": "vol-data",
        "log_groups": {"jumpserver": "/safe/log"},
    }
    inventory = build_inventory(deployment, {"admin": "secret-container-name"}, "us-east-1")
    assert "i-openvpn" in inventory
    assert "secret-container-name" in inventory
    assert "password" not in inventory.lower()
    assert json.dumps("10.250.0.0") in inventory
