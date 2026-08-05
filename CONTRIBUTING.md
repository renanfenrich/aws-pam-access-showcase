# Contributing

1. Start from updated `main` and create one narrowly scoped feature branch.
2. Keep Terraform infrastructure ownership separate from Ansible host/application ownership.
3. Do not deploy while developing repository changes. Use credential-free `make ci`.
4. Use Conventional Commits and keep changes logically scoped.
5. Open a ready-for-review pull request describing architecture/security impact, tests actually run, and limitations.
6. Obtain protected-environment approval only after merge when a live deployment is intended.

Changes that weaken the `/32` route, target source-security-group rule, OIDC subjects, secret handling, immutable pins, SSM-only administration, or destroy safety require an explicit threat-model update.

Local AWS commands must remain compatible with:

```bash
aws-vault exec <profile> -- make <target>
```

Do not report a static check as live deployment proof.
