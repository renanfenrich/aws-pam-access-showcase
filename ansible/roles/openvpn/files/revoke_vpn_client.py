#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import boto3


def write(path: Path, value: str, mode: int = 0o600) -> None:
    path.write_text(value, encoding="utf-8")
    path.chmod(mode)


def main() -> None:
    config: dict[str, str] = json.loads(Path("/etc/aws-pam-vpn.json").read_text(encoding="utf-8"))
    client: Any = boto3.client("secretsmanager", region_name=config["region"])
    bundle = json.loads(client.get_secret_value(SecretId=config["ca_secret"])["SecretString"])
    if bundle.get("revoked"):
        print("already-revoked")
        return
    with tempfile.TemporaryDirectory(prefix="vpn-revoke-") as temporary:
        work = Path(temporary)
        (work / "newcerts").mkdir()
        for filename, key in {
            "ca.key": "ca_key",
            "ca.crt": "ca_cert",
            "demo-client.crt": "client_cert",
            "index.txt": "index",
            "serial": "serial",
            "crlnumber": "crlnumber",
        }.items():
            write(work / filename, bundle[key])
        openssl_config = f"""[ ca ]
default_ca = CA_default
[ CA_default ]
dir = {work}
database = $dir/index.txt
new_certs_dir = $dir/newcerts
certificate = $dir/ca.crt
private_key = $dir/ca.key
serial = $dir/serial
crlnumber = $dir/crlnumber
default_md = sha256
default_days = 30
default_crl_days = 30
policy = policy_any
[ policy_any ]
commonName = supplied
"""
        write(work / "openssl.cnf", openssl_config)
        subprocess.run(
            [
                "/usr/bin/openssl",
                "ca",
                "-batch",
                "-config",
                str(work / "openssl.cnf"),
                "-revoke",
                str(work / "demo-client.crt"),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                "/usr/bin/openssl",
                "ca",
                "-batch",
                "-config",
                str(work / "openssl.cnf"),
                "-gencrl",
                "-out",
                str(work / "crl.pem"),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        bundle.update(
            {
                "crl": (work / "crl.pem").read_text(encoding="utf-8"),
                "index": (work / "index.txt").read_text(encoding="utf-8"),
                "crlnumber": (work / "crlnumber").read_text(encoding="ascii"),
                "revoked": True,
            }
        )
        client.put_secret_value(SecretId=config["ca_secret"], SecretString=json.dumps(bundle))
        client.put_secret_value(
            SecretId=config["profile_secret"],
            SecretString=json.dumps({"revoked": True}),
        )
        shutil.copy2(work / "crl.pem", "/etc/openvpn/server/pki/crl.pem")
        os.chmod("/etc/openvpn/server/pki/crl.pem", 0o644)
    subprocess.run(["/usr/bin/systemctl", "restart", "openvpn-server@server"], check=True)
    print("revoked")


if __name__ == "__main__":
    main()
