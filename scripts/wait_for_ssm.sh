#!/usr/bin/env bash
set -euo pipefail

terraform_dir=${1:?terraform directory is required}
aws_region=${2:?AWS region is required}
deployment=$(terraform -chdir="$terraform_dir" output -json deployment)
instance_ids=$(jq -r '[.openvpn_instance_id,.jumpserver_instance_id,.sensitive_instance_id] | join(",")' <<< "$deployment")

for _ in {1..60}; do
  # Single quotes preserve the JMESPath backticks for the AWS CLI.
  # shellcheck disable=SC2016
  online=$(aws ssm describe-instance-information \
    --region "$aws_region" \
    --filters "Key=InstanceIds,Values=${instance_ids}" \
    --query 'length(InstanceInformationList[?PingStatus==`Online`])' \
    --output text)
  if [[ $online == 3 ]]; then
    printf 'All three instances are online in Systems Manager.\n'
    exit 0
  fi
  sleep 10
done

printf 'Timed out waiting for all instances to become online in Systems Manager.\n' >&2
exit 1
