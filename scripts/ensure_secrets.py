#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import boto3

try:
    from scripts import _terraform as terraform_helper
except ModuleNotFoundError:
    import _terraform as terraform_helper  # type: ignore[no-redef]
from botocore.exceptions import ClientError


def run(*args: str, cwd: Path) -> None:
    subprocess.run(args, cwd=cwd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def secret_exists(client: Any, secret_id: str) -> bool:
    try:
        client.get_secret_value(SecretId=secret_id)
        return True
    except client.exceptions.ResourceNotFoundException:
        return False
    except ClientError as exc:
        if exc.response["Error"]["Code"] in {
            "ResourceNotFoundException",
            "InvalidRequestException",
        }:
            return False
        raise


def put_if_absent(client: Any, secret_id: str, value: str) -> bool:
    if secret_exists(client, secret_id):
        return False
    client.put_secret_value(SecretId=secret_id, SecretString=value)
    return True


def get_secret(client: Any, secret_id: str) -> str:
    return str(client.get_secret_value(SecretId=secret_id)["SecretString"])


def password() -> str:
    return secrets.token_urlsafe(36)


def static_tls_key() -> str:
    body = os.linesep.join(secrets.token_hex(16) for _ in range(16))
    return (
        "#\n# 2048 bit OpenVPN static key\n#\n"
        "-----BEGIN OpenVPN Static key V1-----\n"
        f"{body}\n"
        "-----END OpenVPN Static key V1-----\n"
    )


def create_ssh_key(work: Path) -> dict[str, str]:
    key = work / "id_ed25519"
    run(
        "ssh-keygen",
        "-q",
        "-t",
        "ed25519",
        "-N",
        "",
        "-C",
        "jms-operator",
        "-f",
        str(key),
        cwd=work,
    )
    return {
        "private_key": key.read_text(encoding="utf-8"),
        "public_key": key.with_suffix(".pub").read_text(encoding="utf-8").strip(),
    }


def openssl_config(work: Path) -> Path:
    config = work / "openssl.cnf"
    config.write_text(
        f"""[ ca ]
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
x509_extensions = client_cert
copy_extensions = copy
[ policy_any ]
commonName = supplied
[ req ]
distinguished_name = req_dn
prompt = no
[ req_dn ]
CN = aws-pam-showcase
[ server_cert ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
[ client_cert ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = clientAuth
""",
        encoding="utf-8",
    )
    (work / "index.txt").touch()
    (work / "serial").write_text("1000\n", encoding="ascii")
    (work / "crlnumber").write_text("1000\n", encoding="ascii")
    (work / "newcerts").mkdir()
    return config


def create_openvpn_pki(work: Path, remote_ip: str) -> tuple[dict[str, str], str]:
    config = openssl_config(work)
    run(
        "openssl",
        "genpkey",
        "-algorithm",
        "RSA",
        "-pkeyopt",
        "rsa_keygen_bits:3072",
        "-out",
        "ca.key",
        cwd=work,
    )
    run(
        "openssl",
        "req",
        "-x509",
        "-new",
        "-sha256",
        "-days",
        "30",
        "-key",
        "ca.key",
        "-subj",
        "/CN=AWS PAM Demo VPN CA",
        "-out",
        "ca.crt",
        cwd=work,
    )
    for name, extension in (("server", "server_cert"), ("demo-client", "client_cert")):
        run(
            "openssl",
            "genpkey",
            "-algorithm",
            "RSA",
            "-pkeyopt",
            "rsa_keygen_bits:2048",
            "-out",
            f"{name}.key",
            cwd=work,
        )
        run(
            "openssl",
            "req",
            "-new",
            "-key",
            f"{name}.key",
            "-subj",
            f"/CN={name}",
            "-out",
            f"{name}.csr",
            cwd=work,
        )
        run(
            "openssl",
            "ca",
            "-batch",
            "-config",
            str(config),
            "-extensions",
            extension,
            "-in",
            f"{name}.csr",
            "-out",
            f"{name}.crt",
            cwd=work,
        )
    run("openssl", "ca", "-batch", "-config", str(config), "-gencrl", "-out", "crl.pem", cwd=work)
    tls_key = static_tls_key()
    bundle = {
        "ca_key": (work / "ca.key").read_text(encoding="utf-8"),
        "ca_cert": (work / "ca.crt").read_text(encoding="utf-8"),
        "server_key": (work / "server.key").read_text(encoding="utf-8"),
        "server_cert": (work / "server.crt").read_text(encoding="utf-8"),
        "client_key": (work / "demo-client.key").read_text(encoding="utf-8"),
        "client_cert": (work / "demo-client.crt").read_text(encoding="utf-8"),
        "crl": (work / "crl.pem").read_text(encoding="utf-8"),
        "index": (work / "index.txt").read_text(encoding="utf-8"),
        "serial": (work / "serial").read_text(encoding="ascii"),
        "crlnumber": (work / "crlnumber").read_text(encoding="ascii"),
        "tls_crypt_key": tls_key,
    }
    return bundle, openvpn_profile(bundle, remote_ip)


def openvpn_profile(bundle: dict[str, str], remote_ip: str) -> str:
    return f"""client
dev tun
proto udp
remote {remote_ip} 1194
nobind
remote-cert-tls server
auth-nocache
cipher AES-256-GCM
verb 3
<ca>
{bundle["ca_cert"].strip()}
</ca>
<cert>
{bundle["client_cert"].strip()}
</cert>
<key>
{bundle["client_key"].strip()}
</key>
<tls-crypt>
{bundle["tls_crypt_key"].strip()}
</tls-crypt>
"""


def create_tls_ca(work: Path) -> dict[str, str]:
    run(
        "openssl",
        "genpkey",
        "-algorithm",
        "RSA",
        "-pkeyopt",
        "rsa_keygen_bits:3072",
        "-out",
        "tls-ca.key",
        cwd=work,
    )
    run(
        "openssl",
        "req",
        "-x509",
        "-new",
        "-sha256",
        "-days",
        "30",
        "-key",
        "tls-ca.key",
        "-subj",
        "/CN=AWS PAM Showcase Private CA",
        "-out",
        "tls-ca.crt",
        cwd=work,
    )
    return {
        "private_key": (work / "tls-ca.key").read_text(encoding="utf-8"),
        "certificate": (work / "tls-ca.crt").read_text(encoding="utf-8"),
    }


def shred(work: Path) -> None:
    for item in work.iterdir():
        if item.is_file():
            try:
                size = item.stat().st_size
                with item.open("r+b") as handle:
                    handle.write(b"\0" * size)
                    handle.flush()
                    os.fsync(handle.fileno())
            except OSError:
                pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terraform-dir", type=Path, required=True)
    parser.add_argument("--region", required=True)
    args = parser.parse_args()
    deployment = terraform_helper.terraform_output(args.terraform_dir)["deployment"]
    names: dict[str, str] = deployment["secret_names"]
    client = boto3.client("secretsmanager", region_name=args.region)
    created: list[str] = []

    simple = {
        "jumpserver-secret-key": secrets.token_hex(32),
        "jumpserver-bootstrap-token": secrets.token_hex(32),
        "jumpserver-admin-password": password(),
        "jumpserver-demo-user-password": password(),
        "jumpserver-postgres-password": password(),
        "jumpserver-redis-password": password(),
    }
    for key, value in simple.items():
        if put_if_absent(client, names[key], value):
            created.append(key)

    with tempfile.TemporaryDirectory(prefix="aws-pam-secrets-") as temporary:
        work = Path(temporary)
        try:
            if not secret_exists(client, names["sensitive-resource-ssh-key"]):
                put_if_absent(
                    client, names["sensitive-resource-ssh-key"], json.dumps(create_ssh_key(work))
                )
                created.append("sensitive-resource-ssh-key")

            if not secret_exists(client, names["jumpserver-tls-ca"]):
                tls = create_tls_ca(work)
                put_if_absent(client, names["jumpserver-tls-ca"], json.dumps(tls))
                created.append("jumpserver-tls-ca")
            tls = json.loads(get_secret(client, names["jumpserver-tls-ca"]))
            if put_if_absent(client, names["jumpserver-tls-ca-certificate"], tls["certificate"]):
                created.append("jumpserver-tls-ca-certificate")

            if not secret_exists(client, names["openvpn-ca"]):
                vpn, _ = create_openvpn_pki(work, deployment["openvpn_public_ip"])
                put_if_absent(client, names["openvpn-ca"], json.dumps(vpn))
                created.append("openvpn-ca")
            vpn = json.loads(get_secret(client, names["openvpn-ca"]))
            profile = openvpn_profile(vpn, deployment["openvpn_public_ip"])
            if put_if_absent(client, names["openvpn-demo-client-profile"], profile):
                created.append("openvpn-demo-client-profile")
        finally:
            shred(work)

    print(json.dumps({"created": sorted(created), "preserved": len(names) - len(created)}))


if __name__ == "__main__":
    main()
