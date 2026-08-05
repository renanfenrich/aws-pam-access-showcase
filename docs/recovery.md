# Recovery

JumpServer `SECRET_KEY` and `BOOTSTRAP_TOKEN` are preserved as Secrets Manager values and are never regenerated when a current version exists. The encrypted JumpServer data volume persists the standalone PostgreSQL, Redis, configuration, and recording data for the life of the showcase.

For an interrupted configuration run, confirm the same deployment ID and exact state, then rerun the protected deploy workflow at the same reviewed commit. Terraform and Ansible reconcile existing resources; `ensure_secrets.py` preserves current values.

This repository does not claim production recovery. Before any production use, implement external databases, durable recording storage, versioned backups, cross-failure-domain recovery, restoration drills, defined RPO/RTO, and independent audit evidence retention.

If a key or token is suspected compromised, follow `credential-rotation.md`; do not overwrite Terraform state or delete secret history as an improvised recovery step.
