# Deployment

## Required GitHub variables

| Variable | Location | Meaning |
| --- | --- | --- |
| `AWS_REGION` | repository or each environment | default `us-east-1` |
| `TF_STATE_BUCKET` | all three environments | bootstrap `state_bucket` output |
| `TF_STATE_KMS_KEY_ARN` | all three environments | bootstrap state KMS output |
| `PLAN_ROLE_ARN` | `showcase-plan` | plan role output |
| `DEPLOY_ROLE_ARN` | plan/apply/destroy | deployment role output; also main-stack input |
| `DESTROY_ROLE_ARN` | `showcase-destroy` | destroy role output |
| `PERMISSIONS_BOUNDARY_ARN` | plan/apply/destroy | bootstrap `permissions_boundary_arn` output |
| `DEPLOYMENT_ID` | plan/destroy | deterministic suffix, for example `demo01` |
| `OPERATOR_CIDR` | plan/apply/destroy | explicit operator public CIDR, never `0.0.0.0/0` |
| `AUTHORIZATION_EXPIRATION` | plan/destroy | future RFC3339 time; deploy receives a manual input |
| `EXPIRATION` | plan/apply/destroy | `YYYY-MM-DD` cost-control tag |

Do not configure AWS access-key secrets. The workflows request short-lived role credentials with GitHub OIDC.

The deploy role can mutate only project-prefixed and project-tagged resources. Its `iam:PassRole` grant is limited to the three EC2 instance roles and EC2 as the destination service. The destroy role can inspect, revoke, and delete the tagged showcase but cannot create infrastructure or change role policies.

## First deployment

1. Merge a validated PR to `main`.
2. Open **Actions → Deploy showcase → Run workflow** from `main`.
3. Enter the full `main` commit SHA, region, deployment identifier, future authorization expiration, and `APPLY`.
4. A reviewer other than the initiator approves `showcase-apply` where the GitHub plan supports self-review prevention.
5. Review the job summary and download only the sanitized evidence artifact.

No workflow deploys automatically. A failed deployment must be investigated before retrying; reruns preserve existing secret versions and reconcile configuration idempotently.
