# Third-party components

| Component | Pinned version/reference | Integrity control | Purpose |
| --- | --- | --- | --- |
| Terraform | `1.15.8` | exact version and provider lock files | infrastructure graph/tests |
| AWS provider | `6.58.0` | exact constraint and signed lock checksum | AWS resources |
| JumpServer CE installer | `v4.10.18` | SHA-256 `7a0b...9d3` | PAM deployment |
| JumpServer core | `sha256:13ad...337` | OCI manifest digest | API/core/celery |
| JumpServer Koko | `sha256:a429...eee` | OCI manifest digest | SSH proxy |
| JumpServer web | `sha256:ab76...924` | OCI manifest digest | private UI/TLS proxy |
| PostgreSQL | `sha256:3847...c74` | OCI manifest digest | standalone database |
| Redis | `sha256:a9cc...514` | OCI manifest digest | standalone cache/queue |
| Docker | `29.6.1` | SHA-256 in role defaults | container runtime |
| Docker Compose | `v2.40.3` | SHA-256 in role defaults | installer orchestration |
| OpenVPN Community Edition | signed Amazon Linux package | repository signature | VPN network gate |
| Ansible collections | exact versions in `ansible/requirements.yml` | Galaxy package install | SSM, crypto, POSIX modules |
| GitHub Actions | full 40-character commit SHA plus release comment | immutable Git commit | checkout, tool setup, OIDC, evidence upload |

Licenses remain with their upstream projects. JumpServer CE is GPL-3.0; OpenVPN Community Edition is GPL-2.0; Terraform and providers/actions use their respective upstream licenses. Review upstream license and notice files before redistribution.

The JumpServer installer itself contains additional component definitions that are disabled for this SSH-only showcase. Relevant enabled image references are replaced with immutable digests before execution.
