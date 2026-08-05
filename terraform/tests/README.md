# Terraform test routing

Native Terraform tests live beside each root so `terraform test` can resolve relative modules:

- `bootstrap/tests/bootstrap.tftest.hcl`
- `terraform/environments/showcase/tests/showcase.tftest.hcl`
