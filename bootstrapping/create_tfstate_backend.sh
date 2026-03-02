#!/usr/bin/env bash
set -euo pipefail

# This script creates an S3 bucket for Terraform remote state.
# Resources are created with aws-assessment-ci-* prefix.

export AWS_REGION="${AWS_REGION:-us-east-1}"

PREFIX="aws-assessment-ci"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PREFIX}-tfstate-guillemtp-${AWS_REGION}"
echo "Using account: ${ACCOUNT_ID}"
echo "Ensuring state bucket exists: ${STATE_BUCKET}"

if aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  echo "Bucket already exists."
else
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${STATE_BUCKET}" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}" >/dev/null
  fi
fi

# Enable versioning to keep state history.
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled >/dev/null

# Enforce server-side encryption.
aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' >/dev/null

# Block any public access for security.
aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

echo "S3 backend bucket ready: ${STATE_BUCKET}"
echo "Update terraform/backend.hcl bucket value and run:"
echo "make tf-init PROJECT_NAME=<your-project-name>"
