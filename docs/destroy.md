# Destroy

The `showcase-destroy` environment is a separate approval boundary and assumes `GitHubDestroyRole`. Run `destroy.yml` from `main` with the exact reviewed commit, exact deployment identifier, and confirmation `DESTROY`.

The workflow:

1. checks the deployment identifier;
2. captures a sanitized inventory containing roles and resource classes only;
3. revokes the demo VPN certificate through Systems Manager;
4. runs Terraform destroy for the main stack, scheduling Secrets Manager and KMS deletion according to their recovery windows;
5. queries tagged resources and fails if a chargeable non-pending-deletion resource remains;
6. preserves the bootstrap state bucket, state KMS key, and OIDC roles.

Destroy the bootstrap separately only after all main states are gone, state retention requirements are met, and the repository no longer needs OIDC. The bootstrap state bucket has `prevent_destroy`; removing it is an explicit operator procedure, not part of this showcase workflow.
