#!/usr/bin/env bash
set -euo pipefail

# This script removes IAM CI resources created by create_ci_user.sh.
# It deletes user access keys, detaches policies, deletes the user, and deletes the policy.

export AWS_REGION="${AWS_REGION:-us-east-1}"

CI_PREFIX="aws-assessment-ci"
CI_USER_NAME="${CI_PREFIX}-user"
CI_POLICY_NAME="${CI_PREFIX}-terraform-policy"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${CI_POLICY_NAME}"

echo "Using account: ${ACCOUNT_ID}"
echo "Deleting CI resources for prefix: ${CI_PREFIX}"

if aws iam get-user --user-name "${CI_USER_NAME}" >/dev/null 2>&1; then
  echo "Deleting access keys for user ${CI_USER_NAME}"
  while IFS= read -r key_id; do
    [ -n "${key_id}" ] || continue
    aws iam delete-access-key --user-name "${CI_USER_NAME}" --access-key-id "${key_id}" >/dev/null
  done < <(aws iam list-access-keys --user-name "${CI_USER_NAME}" --query 'AccessKeyMetadata[].AccessKeyId' --output text | tr '\t' '\n')

  echo "Detaching managed policies from user ${CI_USER_NAME}"
  while IFS= read -r attached_policy_arn; do
    [ -n "${attached_policy_arn}" ] || continue
    aws iam detach-user-policy --user-name "${CI_USER_NAME}" --policy-arn "${attached_policy_arn}" >/dev/null
  done < <(aws iam list-attached-user-policies --user-name "${CI_USER_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text | tr '\t' '\n')

  echo "Deleting user ${CI_USER_NAME}"
  aws iam delete-user --user-name "${CI_USER_NAME}" >/dev/null
else
  echo "User ${CI_USER_NAME} does not exist, skipping"
fi

if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  echo "Deleting non-default policy versions"
  while IFS= read -r version_id; do
    [ -n "${version_id}" ] || continue
    aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${version_id}" >/dev/null
  done < <(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text | tr '\t' '\n')

  echo "Deleting policy ${CI_POLICY_NAME}"
  aws iam delete-policy --policy-arn "${POLICY_ARN}" >/dev/null
else
  echo "Policy ${CI_POLICY_NAME} does not exist, skipping"
fi

echo "Cleanup completed."
