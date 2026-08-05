# Credential rotation and revocation

| Credential | Operation |
| --- | --- |
| Target SSH key | Protected `make rotate-credentials`; creates a new secret version, installs the public key on the target, then updates the JumpServer managed account |
| OpenVPN client | `revoke_vpn_client.yml`; revokes the certificate, publishes a new CRL, replaces the current profile value with a revoked marker, and restarts OpenVPN |
| JumpServer demo password | Create a cryptographically random new secret version, update the user through the pinned API, and require login/MFA proof |
| JumpServer admin password | Create a new secret version and rerun the password reconciliation step through SSM |
| `SECRET_KEY` / `BOOTSTRAP_TOKEN` | Recovery-sensitive; rotate only with the JumpServer documented procedure and a tested backup |
| Private TLS CA | Reissue CA/server certificates, redistribute only the public CA, and remove the previous trust anchor after a controlled overlap |

Rotation workflows must retain `no_log`, avoid artifacts, and clean temporary runner files. Revocation is not complete until the old credential is tested and rejected.
