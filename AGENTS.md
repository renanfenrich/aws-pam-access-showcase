# Contributor instructions

- Never run `terraform apply`, `terraform destroy`, or an AWS mutation unless the operator explicitly requests it.
- Treat `deployment_enabled = false` as the safe local default.
- Keep Terraform responsible for infrastructure and Ansible responsible for host configuration.
- Never print, persist, commit, or upload secret values, Terraform state, VPN profiles, or private keys.
- Pin third-party Actions to full commit SHAs and explain every exception to immutable image digests.
- Report only checks actually run and preserve the distinction between static and deployed evidence.
