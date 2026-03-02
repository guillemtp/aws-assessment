# Bootstrapping

This folder contains scripts to create and remove resources used by CI and Terraform remote state.
All resources are created with the `aws-assessment-ci-*` prefix.

## Requirements

- AWS CLI v2
- `jq`
- IAM permissions to create/delete users, policies, access keys, and attachments
- IAM permissions to create/delete S3 buckets and bucket settings

## Create CI user and credentials

```bash
chmod +x bootstrapping/*.sh
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/create_ci_user.sh
```

The script prints:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Store both values in GitHub Actions secrets.

## Delete CI resources

```bash
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/destroy_ci_user.sh
```

## Create S3 backend for Terraform state

```bash
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/create_tfstate_backend.sh
```

Then update `terraform/backend.hcl` with that bucket value and initialize Terraform:

```bash
make tf-init PROJECT_NAME=aws-assessment
```

Terraform state key format is:

```text
<project_name>/terraform.tfstate
```

## Delete S3 backend bucket

```bash
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/destroy_tfstate_backend.sh
```
