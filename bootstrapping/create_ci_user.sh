#!/usr/bin/env bash
set -euo pipefail

# This script creates a dedicated IAM user + policy for GitHub Actions CI.
# All created resources use the aws-assessment-ci-* prefix.

# Required: valid AWS credentials with IAM admin privileges.
# Optional env vars:
# - AWS_PROFILE (example: personal-admin)
# - AWS_REGION  (default: us-east-1)

export AWS_REGION="${AWS_REGION:-us-east-1}"

CI_PREFIX="aws-assessment-ci"
CI_USER_NAME="${CI_PREFIX}-user"
CI_POLICY_NAME="${CI_PREFIX}-terraform-policy"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${CI_POLICY_NAME}"

echo "Using account: ${ACCOUNT_ID}"
echo "Creating/ensuring policy: ${CI_POLICY_NAME}"

tmp_policy_file="$(mktemp)"
cat > "${tmp_policy_file}" <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformIdentityRead",
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    },
    {
      "Sid": "RegionalInfraManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc","ec2:DeleteVpc","ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet","ec2:DeleteSubnet","ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway","ec2:DeleteInternetGateway","ec2:AttachInternetGateway","ec2:DetachInternetGateway",
        "ec2:CreateRouteTable","ec2:DeleteRouteTable","ec2:CreateRoute","ec2:ReplaceRoute","ec2:DeleteRoute",
        "ec2:AssociateRouteTable","ec2:DisassociateRouteTable",
        "ec2:CreateSecurityGroup","ec2:DeleteSecurityGroup","ec2:AuthorizeSecurityGroupIngress","ec2:AuthorizeSecurityGroupEgress","ec2:RevokeSecurityGroupIngress","ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags","ec2:DeleteTags",
        "ec2:Describe*",
        "lambda:*",
        "apigateway:*",
        "logs:*",
        "dynamodb:*",
        "ecs:*",
        "cognito-idp:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "eu-west-1"]
        }
      }
    },
    {
      "Sid": "PublishOnlyToVerificationTopic",
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
    },
    {
      "Sid": "TerraformStateBucketList",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ],
      "Resource": "arn:aws:s3:::aws-assessment-ci-tfstate-*"
    },
    {
      "Sid": "TerraformStateObjectReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "arn:aws:s3:::aws-assessment-ci-tfstate-*/*"
    },
    {
      "Sid": "IamForAssessmentRolesOnly",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole","iam:DeleteRole","iam:GetRole","iam:UpdateAssumeRolePolicy","iam:TagRole","iam:UntagRole",
        "iam:ListInstanceProfilesForRole",
        "iam:PutRolePolicy","iam:DeleteRolePolicy","iam:GetRolePolicy","iam:ListRolePolicies",
        "iam:AttachRolePolicy","iam:DetachRolePolicy","iam:ListAttachedRolePolicies",
        "iam:CreatePolicy","iam:DeletePolicy","iam:GetPolicy","iam:GetPolicyVersion","iam:CreatePolicyVersion","iam:DeletePolicyVersion","iam:ListPolicyVersions",
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::${ACCOUNT_ID}:role/aws-assessment-*",
        "arn:aws:iam::${ACCOUNT_ID}:policy/aws-assessment-*"
      ]
    },
    {
      "Sid": "ReadIamMetadata",
      "Effect": "Allow",
      "Action": ["iam:ListPolicies", "iam:ListRoles"],
      "Resource": "*"
    }
  ]
}
POLICY

if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  echo "Policy already exists, creating a new default version."
  # IAM managed policies support at most 5 versions.
  # Delete the oldest non-default version before creating a new one if needed.
  versions_json="$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}")"
  versions_count="$(echo "${versions_json}" | jq '.Versions | length')"
  if [ "${versions_count}" -ge 5 ]; then
    oldest_non_default="$(echo "${versions_json}" | jq -r '.Versions | map(select(.IsDefaultVersion == false)) | sort_by(.CreateDate) | .[0].VersionId')"
    if [ "${oldest_non_default}" != "null" ]; then
      aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${oldest_non_default}" >/dev/null
    fi
  fi

  aws iam create-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --policy-document "file://${tmp_policy_file}" \
    --set-as-default >/dev/null

  # Optional cleanup after update (keeps policy tidy).
  versions_json="$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}")"
  versions_count="$(echo "${versions_json}" | jq '.Versions | length')"
  if [ "${versions_count}" -gt 4 ]; then
    oldest_non_default="$(echo "${versions_json}" | jq -r '.Versions | map(select(.IsDefaultVersion == false)) | sort_by(.CreateDate) | .[0].VersionId')"
    if [ "${oldest_non_default}" != "null" ]; then
      aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${oldest_non_default}" >/dev/null
    fi
  fi
else
  aws iam create-policy \
    --policy-name "${CI_POLICY_NAME}" \
    --policy-document "file://${tmp_policy_file}" >/dev/null
fi

echo "Creating/ensuring user: ${CI_USER_NAME}"
if ! aws iam get-user --user-name "${CI_USER_NAME}" >/dev/null 2>&1; then
  aws iam create-user --user-name "${CI_USER_NAME}" >/dev/null
fi

echo "Attaching policy to user"
aws iam attach-user-policy --user-name "${CI_USER_NAME}" --policy-arn "${POLICY_ARN}" >/dev/null

echo "Creating a new access key"
access_key_json="$(aws iam create-access-key --user-name "${CI_USER_NAME}")"

ACCESS_KEY_ID="$(echo "${access_key_json}" | jq -r '.AccessKey.AccessKeyId')"
SECRET_ACCESS_KEY="$(echo "${access_key_json}" | jq -r '.AccessKey.SecretAccessKey')"

echo
echo "Created CI credentials. Save them now (secret is only shown once):"
echo "AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}"
echo "AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}"
echo
echo "Add these values to GitHub Actions secrets:"
echo "- AWS_ACCESS_KEY_ID"
echo "- AWS_SECRET_ACCESS_KEY"

rm -f "${tmp_policy_file}"
