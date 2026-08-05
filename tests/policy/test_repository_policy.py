from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).parents[2]


def files(pattern: str) -> list[Path]:
    return list(ROOT.glob(pattern))


def test_required_repository_structure() -> None:
    required = [
        "README.md",
        "SECURITY.md",
        "CONTRIBUTING.md",
        "THIRD_PARTY.md",
        "AGENTS.md",
        "bootstrap/main.tf",
        "terraform/environments/showcase/main.tf",
        "ansible/playbooks/configure.yml",
        "ansible/playbooks/verify.yml",
        ".github/workflows/ci.yml",
        ".github/workflows/plan.yml",
        ".github/workflows/deploy.yml",
        ".github/workflows/destroy.yml",
    ]
    assert not [item for item in required if not (ROOT / item).is_file()]


def test_actions_are_pinned_to_full_shas() -> None:
    uses = re.compile(r"^\s*uses:\s*[^#\s]+@([^\s#]+)", re.MULTILINE)
    for workflow in files(".github/workflows/*.yml"):
        for ref in uses.findall(workflow.read_text(encoding="utf-8")):
            assert re.fullmatch(r"[0-9a-f]{40}", ref), f"mutable action ref in {workflow}: {ref}"


def test_ci_has_no_aws_authentication() -> None:
    ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert "configure-aws-credentials" not in ci
    assert "id-token: write" not in ci


def test_no_static_aws_credentials_are_configured() -> None:
    workflow_text = "\n".join(
        path.read_text(encoding="utf-8") for path in files(".github/workflows/*.yml")
    )
    assert "AWS_ACCESS_KEY_ID" not in workflow_text
    assert "AWS_SECRET_ACCESS_KEY" not in workflow_text
    assert "AWS_SESSION_TOKEN" not in workflow_text


def test_terraform_has_no_provisioners_or_generated_secrets() -> None:
    terraform = "\n".join(path.read_text(encoding="utf-8") for path in files("**/*.tf"))
    assert 'provisioner "remote-exec"' not in terraform
    assert 'provisioner "local-exec"' not in terraform
    assert "random_password" not in terraform
    assert "aws_secretsmanager_secret_version" not in terraform


def test_ec2_controls_are_explicit() -> None:
    modules = "\n".join(
        path.read_text(encoding="utf-8")
        for path in files("terraform/modules/*/main.tf")
        if "aws_instance" in path.read_text(encoding="utf-8")
    )
    assert modules.count('http_tokens                 = "required"') == 3
    assert "key_name" not in modules
    assert modules.count("encrypted   = true") >= 3


def test_deployment_interlock_defaults_off() -> None:
    variables = (ROOT / "terraform/environments/showcase/variables.tf").read_text(encoding="utf-8")
    match = re.search(r'variable "deployment_enabled"\s*\{(?P<body>.*?)\n\}', variables, re.DOTALL)
    assert match
    assert "default     = false" in match.group("body")


def test_sensitive_ssh_uses_only_jumpserver_group() -> None:
    security = (ROOT / "terraform/environments/showcase/security.tf").read_text(encoding="utf-8")
    rule = re.search(
        r'resource "aws_vpc_security_group_ingress_rule" "sensitive_ssh"\s*\{(?P<body>.*?)\n\}',
        security,
        re.DOTALL,
    )
    assert rule
    assert "referenced_security_group_id = aws_security_group.jumpserver.id" in rule.group("body")
    assert "cidr_ipv4" not in rule.group("body")


def test_no_secret_bearing_evidence_is_tracked() -> None:
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    assert "evidence/*" in ignore
    assert "!evidence/.gitkeep" in ignore
