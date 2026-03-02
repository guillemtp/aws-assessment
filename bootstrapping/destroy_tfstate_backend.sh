#!/usr/bin/env bash
set -euo pipefail

# This script deletes the Terraform state bucket created by create_tfstate_backend.sh.
# WARNING: this permanently removes all objects and versions in that bucket.

export AWS_REGION="${AWS_REGION:-us-east-1}"

PREFIX="aws-assessment-ci"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PREFIX}-tfstate-${ACCOUNT_ID}-${AWS_REGION}"

echo "Using account: ${ACCOUNT_ID}"
echo "Deleting state bucket: ${STATE_BUCKET}"

if ! aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  echo "Bucket does not exist, nothing to do."
  exit 0
fi

# Delete all object versions and delete markers before bucket deletion.
versions_json="$(aws s3api list-object-versions --bucket "${STATE_BUCKET}" --output json)"

echo "${versions_json}" | jq -c '.Versions[]? | {Key: .Key, VersionId: .VersionId}' | while IFS= read -r item; do
  key="$(echo "${item}" | jq -r '.Key')"
  vid="$(echo "${item}" | jq -r '.VersionId')"
  aws s3api delete-object --bucket "${STATE_BUCKET}" --key "${key}" --version-id "${vid}" >/dev/null
 done

echo "${versions_json}" | jq -c '.DeleteMarkers[]? | {Key: .Key, VersionId: .VersionId}' | while IFS= read -r item; do
  key="$(echo "${item}" | jq -r '.Key')"
  vid="$(echo "${item}" | jq -r '.VersionId')"
  aws s3api delete-object --bucket "${STATE_BUCKET}" --key "${key}" --version-id "${vid}" >/dev/null
 done

aws s3api delete-bucket --bucket "${STATE_BUCKET}" >/dev/null

echo "Bucket deleted."
