# AWS Assessment (Terraform)

This repository implements the Unleash live assessment using Terraform with a multi-region deployment:
- Authentication in `us-east-1` (Cognito User Pool + User Pool Client + test user)
- Regional compute stacks in `us-east-1` and `eu-west-1`
- HTTP API routes (`/greet`, `/dispatch`) protected by Cognito JWT authorizer
- DynamoDB regional logging
- Lambda greeter and Lambda dispatcher
- ECS Fargate one-shot task to publish verification payload to SNS
- Dry-run mode enabled by default (`sns_publish_enabled = false`) to avoid accidental SNS publishes

## Architecture

- Root module defines two aliased AWS providers:
  - `aws.use1` for `us-east-1`
  - `aws.euw1` for `eu-west-1`
- Terraform code lives under `terraform/`.
- `terraform/modules/auth` is deployed once in `us-east-1`.
- `terraform/modules/regional_stack` is deployed twice (one per region) with identical resources.

## Prerequisites

- Docker
- GNU Make
- AWS account/sandbox credentials configured locally
- Python 3.10+ for test script

## Configure variables

```bash
cp .env.example .env
```

Edit `.env`:

- `project_name`: project identifier used in resource naming and Terraform state key
- `candidate_email`: use the same email used with recruiting
- `REPO_OWNER`: your GitHub username/org (mapped to Terraform `github_user`)
- `test_user_password`: password for Cognito test user
- `sns_publish_enabled`: keep `false` for dry run; set `true` only when you want to send verification SNS messages

The Makefile treats `.env` as the single source of truth and generates `terraform.tfvars` automatically (`make tfvars`) before Terraform actions.

## Deploy

Bootstrap remote state bucket:

```bash
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/create_tfstate_backend.sh
```

Then update `terraform/backend.hcl` with the bucket name printed by the script, and initialize Terraform:

```bash
make tf-init
```

Then deploy:

```bash
make tf-fmt
make tf-validate
make tf-plan
make tf-apply
```

If you want non-interactive apply:

```bash
make tf-apply-auto
```

For the final verification run, enable SNS publishes explicitly:

```bash
make tf-apply-live
```

Or non-interactive:

```bash
make tf-apply-live-auto
```

## Run e2e tests

End-to-end tests use `pytest + httpx + boto3`, executed in Docker:

```bash
make tests
```

This command also writes a JUnit report at `test-results/pytest.xml`.

## Makefile wrapper

Common commands are available via `Makefile`:
- `make tfvars`
- `make tf-init`
- `make tf-fmt`
- `make tf-validate`
- `make tf-plan`
- `make tf-apply`
- `make tf-apply-auto`
- `make tf-destroy`
- `make tf-output`
- `make tf-apply-live`
- `make tf-apply-live-auto`
- `make tests`

By default, `make tf-*` runs Terraform inside Docker (`hashicorp/terraform:1.10.5`), so local Terraform installation is not required.
The container reads AWS credentials from `~/.aws` (mounted read-only) or from exported `AWS_*` environment variables.
State is always stored in S3 remote backend, and locking uses S3 native lockfiles (`use_lockfile = true`), so DynamoDB locking is not required.
`terraform.tfvars` is auto-generated from `.env` by the Makefile.

## CI/CD

GitHub Actions pipeline: `.github/workflows/deploy.yml`

Includes:
- Terraform format check
- Terraform validate
- Security scan (`tfsec`)
- Terraform init with remote S3 backend (when required AWS/app/backend secrets are configured)
- Terraform plan/apply
- Automated pytest e2e execution with JUnit report output
- Test report publication in GitHub Actions summary/checks
- Automatic teardown with `terraform destroy` at the end (`always()` safeguard)

Required CI secrets for deploy/test/destroy:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `PROJECT_NAME` (optional, defaults to `aws-assessment`)
- `CANDIDATE_EMAIL`
- `TEST_USER_PASSWORD`
- `REPO_OWNER` (GitHub username/org used as `github_user` in Terraform payload)

Recommended CI repository variables (non-sensitive):
- `AWS_REGION` (default `us-east-1`)

The workflow derives backend bucket name automatically as:
`aws-assessment-ci-tfstate-<account_id>-<AWS_REGION>`.

## CI bootstrapping (AWS CLI)

If you want to create a limited IAM user for GitHub Actions with prefix `aws-assessment-ci-*`, use:

```bash
chmod +x bootstrapping/*.sh
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/create_ci_user.sh
```

The script prints credentials that you must store as GitHub Actions secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

To delete all CI IAM resources created by the script:

```bash
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/destroy_ci_user.sh
```

To create and remove the Terraform remote-state bucket:

```bash
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/create_tfstate_backend.sh
AWS_PROFILE=personal-admin AWS_REGION=us-east-1 ./bootstrapping/destroy_tfstate_backend.sh
```

## Important: Tear down after validation

Destroy infra after SNS verification to avoid charges:

```bash
make tf-destroy
```
