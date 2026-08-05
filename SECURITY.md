# Security policy

## Reporting

Do not open a public issue containing credentials, account IDs, private addresses, session identifiers, Terraform state, VPN profiles, or exploit details. Report suspected vulnerabilities privately to the repository owner through GitHub Security Advisories.

Include the affected commit, component, reproduction with all secrets removed, impact, and suggested containment. Treat leaked demonstration credentials as compromised even if the environment is scheduled for destroy.

## Supported scope

Only the current `main` branch is supported. This repository is a demonstration, not a managed service or production security guarantee.

## Operator rules

- Never bypass `deployment_enabled`, protected environments, exact-commit checks, or confirmation values.
- Never add inbound administrative SSH, broad VPN routes, `0.0.0.0/0` JumpServer rules, or static AWS credentials.
- Never commit or artifact Terraform state, secret values, VPN profiles, private keys, MFA seeds, or raw recordings.
- Rotate any value that appears in a log, screenshot, issue, or untrusted workstation.
- Destroy the showcase promptly after evidence collection.
