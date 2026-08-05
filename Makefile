SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

TF_ROOT := terraform/environments/showcase
BOOTSTRAP_ROOT := bootstrap
INVENTORY := ansible/inventories/generated.yml
DEPLOYMENT_ID ?= demo
AWS_REGION ?= us-east-1
TF_VARS ?=

.PHONY: bootstrap-init bootstrap-plan bootstrap-apply fmt lint validate test ci plan apply configure verify evidence rotate-credentials revoke-vpn-client destroy inventory

bootstrap-init:
	terraform -chdir=$(BOOTSTRAP_ROOT) init

bootstrap-plan:
	terraform -chdir=$(BOOTSTRAP_ROOT) plan $(TF_VARS)

bootstrap-apply:
	terraform -chdir=$(BOOTSTRAP_ROOT) apply $(TF_VARS)

fmt:
	terraform fmt -recursive
	ruff format scripts tests ansible/roles/jumpserver_bootstrap/files ansible/roles/openvpn/files

lint:
	terraform fmt -check -recursive
	tflint --recursive --config "$$(pwd)/.tflint.hcl"
	ruff check scripts tests ansible/roles/jumpserver_bootstrap/files ansible/roles/openvpn/files
	ruff format --check scripts tests ansible/roles/jumpserver_bootstrap/files ansible/roles/openvpn/files
	mypy scripts
	yamllint .github ansible
	ansible-lint ansible
	shellcheck scripts/*.sh
	actionlint
	zizmor --pedantic .github/workflows
	gitleaks detect --no-banner --redact --no-git
	trivy config --exit-code 1 --severity HIGH,CRITICAL --skip-dirs .ansible --skip-dirs .venv --skip-dirs .terraform --skip-dirs .tools .
	npx --yes markdownlint-cli2@0.20.0 "*.md" "docs/**/*.md" "terraform/**/*.md"

validate:
	terraform -chdir=$(BOOTSTRAP_ROOT) init -backend=false
	terraform -chdir=$(BOOTSTRAP_ROOT) validate
	terraform -chdir=$(TF_ROOT) init -backend=false
	terraform -chdir=$(TF_ROOT) validate
	ansible-playbook --syntax-check ansible/playbooks/configure.yml
	ansible-playbook --syntax-check ansible/playbooks/verify.yml

test:
	terraform -chdir=$(BOOTSTRAP_ROOT) test
	terraform -chdir=$(TF_ROOT) test
	pytest

ci: lint validate test

plan:
	terraform -chdir=$(TF_ROOT) init
	terraform -chdir=$(TF_ROOT) plan -detailed-exitcode -var deployment_enabled=true $(TF_VARS)

apply:
	@test "$${CONFIRM_APPLY:-}" = APPLY || { echo "Set CONFIRM_APPLY=APPLY" >&2; exit 2; }
	terraform -chdir=$(TF_ROOT) apply -var deployment_enabled=true $(TF_VARS)

inventory:
	python3 scripts/build_inventory.py --terraform-dir $(TF_ROOT) --output $(INVENTORY) --region $(AWS_REGION)

configure: inventory
	ansible-playbook -i $(INVENTORY) ansible/playbooks/configure.yml

verify: inventory
	ansible-playbook -i $(INVENTORY) ansible/playbooks/verify.yml
	python3 scripts/verify_aws.py --terraform-dir $(TF_ROOT) --evidence-dir evidence --region $(AWS_REGION)

evidence:
	python3 scripts/summarize_evidence.py evidence

rotate-credentials: inventory
	ansible-playbook -i $(INVENTORY) ansible/playbooks/rotate_demo_credentials.yml

revoke-vpn-client: inventory
	ansible-playbook -i $(INVENTORY) ansible/playbooks/revoke_vpn_client.yml

destroy:
	@test "$${CONFIRM_DESTROY:-}" = DESTROY || { echo "Set CONFIRM_DESTROY=DESTROY" >&2; exit 2; }
	terraform -chdir=$(TF_ROOT) destroy -var deployment_enabled=true $(TF_VARS)
