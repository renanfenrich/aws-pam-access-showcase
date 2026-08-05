# Bootstrap

The separate `bootstrap/` root creates the encrypted/versioned S3 backend, native S3 lockfile support, KMS key, account-level GitHub OIDC provider when requested, and three roles with exact repository/environment subjects.

## Local inputs

```hcl
aws_region                 = "us-east-1"
name_suffix                = "unique01"
github_owner               = "octavarium-digital-partners"
github_repository          = "aws-pam-access-showcase"
create_github_oidc_provider = true
```

If the account already has `token.actions.githubusercontent.com`, set `create_github_oidc_provider = false`; the stack reads the existing provider instead of attempting a duplicate.

```bash
aws-vault exec <profile> -- make bootstrap-init
aws-vault exec <profile> -- make bootstrap-plan TF_VARS='-var-file=terraform.tfvars'
aws-vault exec <profile> -- make bootstrap-apply TF_VARS='-var-file=terraform.tfvars'
```

Review the exact plan before apply. Never commit `bootstrap/terraform.tfvars` or bootstrap state. The main stack never owns its backend or initial OIDC trust.

## GitHub environments

Create these environments and configure required reviewers:

| Environment | OIDC role | Required protection |
| --- | --- | --- |
| `showcase-plan` | output `github_role_arns.plan` | trusted branches; optional review |
| `showcase-apply` | output `github_role_arns.deploy` | required review, `main` only, prevent self-review where supported |
| `showcase-destroy` | output `github_role_arns.destroy` | required review, `main` only, prevent self-review where supported |

GitHub protection settings are repository configuration and cannot be reliably created from this repository without a separate administrative credential.
