UID := $(shell id -u)
GID := $(shell id -g)

-include .env

TFVARS_FILE ?= terraform/terraform.tfvars
TERRAFORM_DIR ?= terraform

TF_DOCKER_IMAGE ?= hashicorp/terraform:1.10.5
OUTPUTS_JSON ?= outputs.json
TEST_RESULTS_DIR ?= test-results
BACKEND_CONFIG ?= backend.hcl
PROJECT_NAME ?= aws-assessment
SNS_PUBLISH_ENABLED ?= false

BACKEND_CONFIG_IN_TF_DIR := $(patsubst $(TERRAFORM_DIR)/%,%,$(BACKEND_CONFIG))

TEST_USERNAME ?= $(CANDIDATE_EMAIL)
TEST_PASSWORD ?= $(TEST_USER_PASSWORD)

strip_quotes = $(patsubst "%",%,$(patsubst '%',%,$(1)))
PROJECT_NAME := $(call strip_quotes,$(PROJECT_NAME))
CANDIDATE_EMAIL := $(call strip_quotes,$(CANDIDATE_EMAIL))
REPO_OWNER := $(call strip_quotes,$(REPO_OWNER))
TEST_USER_PASSWORD := $(call strip_quotes,$(TEST_USER_PASSWORD))
TEST_USERNAME := $(call strip_quotes,$(TEST_USERNAME))
TEST_PASSWORD := $(call strip_quotes,$(TEST_PASSWORD))
AWS_PROFILE := $(call strip_quotes,$(AWS_PROFILE))
BACKEND_CONFIG := $(call strip_quotes,$(BACKEND_CONFIG))

export AWS_PROFILE AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export BACKEND_CONFIG PROJECT_NAME SNS_PUBLISH_ENABLED
export CANDIDATE_EMAIL REPO_OWNER TEST_USER_PASSWORD TEST_USERNAME TEST_PASSWORD TFVARS_FILE OUTPUTS_JSON TF_DOCKER_IMAGE

TF_DOCKER_BASE = docker run --rm \
	-i \
	--user $(UID):$(GID) \
	-v "$(PWD):/work" \
	-w /work/$(TERRAFORM_DIR) \
	-e AWS_PROFILE \
	-e AWS_REGION \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	-e AWS_CONFIG_FILE=/.aws/config \
	-e AWS_SHARED_CREDENTIALS_FILE=/.aws/credentials \
	-e AWS_SDK_LOAD_CONFIG=1 \
	-v "$(HOME)/.aws:/.aws:ro" \
	$(TF_DOCKER_IMAGE)

TF = $(TF_DOCKER_BASE)

TF_INIT_BACKEND_ARGS = -backend-config=$(BACKEND_CONFIG_IN_TF_DIR) -backend-config=key=$(PROJECT_NAME)/terraform.tfstate

.PHONY: help tfvars tf-init tf-fmt tf-validate tf-plan tf-apply tf-apply-auto tf-plan-live tf-apply-live tf-apply-live-auto tf-destroy tf-output tests

help:
	@echo "Targets:"
	@echo "  tfvars         -> generate terraform.tfvars from .env values"
	@echo "  tf-init        -> terraform init (docker by default)"
	@echo "  tf-fmt         -> terraform fmt -recursive (docker by default)"
	@echo "  tf-validate    -> terraform validate (docker by default)"
	@echo "  tf-plan        -> terraform plan (docker by default)"
	@echo "  tf-apply       -> terraform apply (docker by default)"
	@echo "  tf-apply-auto  -> terraform apply -auto-approve"
	@echo "  tf-destroy     -> terraform destroy (docker by default)"
	@echo "  tf-output      -> terraform output -json > $(OUTPUTS_JSON) (docker by default)"
	@echo "  tf-plan-live   -> terraform plan -var 'sns_publish_enabled=true'"
	@echo "  tf-apply-live  -> terraform apply -var 'sns_publish_enabled=true'"
	@echo "  tf-apply-live-auto -> terraform apply -auto-approve -var 'sns_publish_enabled=true'"
	@echo "  tests          -> run pytest e2e in docker (auto-refreshes outputs.json)"
	@echo "Variables:"
	@echo "  .env           -> required source of truth for local/CI inputs"
	@echo "  TF_DOCKER_IMAGE=hashicorp/terraform:1.10.5"
	@echo "  TERRAFORM_DIR=terraform -> IaC root folder"
	@echo "  BACKEND_CONFIG=backend.hcl (or terraform/backend.hcl) -> remote S3 backend config file"
	@echo "  PROJECT_NAME=aws-assessment -> used for both resource names and state key"
	@echo "  CANDIDATE_EMAIL/REPO_OWNER/TEST_USER_PASSWORD -> required for tfvars generation"

tfvars:
	@test -n "$(PROJECT_NAME)" || (echo "PROJECT_NAME is required" && exit 1)
	@test -n "$(CANDIDATE_EMAIL)" || (echo "CANDIDATE_EMAIL is required" && exit 1)
	@test -n "$(REPO_OWNER)" || (echo "REPO_OWNER is required" && exit 1)
	@test -n "$(TEST_USER_PASSWORD)" || (echo "TEST_USER_PASSWORD is required" && exit 1)
	@mkdir -p "$(TERRAFORM_DIR)"
	@{ \
		esc() { printf '%s' "$$1" | sed 's/\\/\\\\/g; s/\"/\\"/g'; }; \
		echo "project_name           = \"`esc "$(PROJECT_NAME)"`\""; \
		echo "candidate_email        = \"`esc "$(CANDIDATE_EMAIL)"`\""; \
		echo "github_user            = \"`esc "$(REPO_OWNER)"`\""; \
		echo "test_user_password     = \"`esc "$(TEST_USER_PASSWORD)"`\""; \
		echo "sns_publish_enabled    = $(SNS_PUBLISH_ENABLED)"; \
		if [ -n "$(AWS_PROFILE)" ]; then echo "aws_profile            = \"`esc "$(AWS_PROFILE)"`\""; fi; \
	} > "$(TFVARS_FILE)"

tf-init: tfvars
	@test -f "$(TERRAFORM_DIR)/$(BACKEND_CONFIG_IN_TF_DIR)" || (echo "Backend config not found: $(BACKEND_CONFIG)" && exit 1)
	$(TF) init -reconfigure $(TF_INIT_BACKEND_ARGS)

tf-fmt:
	$(TF) fmt -recursive

tf-validate: tfvars
	$(TF) validate

tf-plan: tfvars
	$(TF) plan

tf-apply: tfvars
	$(TF) apply

tf-apply-auto: tfvars
	$(TF) apply -auto-approve

tf-plan-live: tfvars
	$(TF) plan -var 'sns_publish_enabled=true'

tf-apply-live: tfvars
	$(TF) apply -var 'sns_publish_enabled=true'

tf-apply-live-auto: tfvars
	$(TF) apply -auto-approve -var 'sns_publish_enabled=true'

tf-destroy: tfvars
	$(TF) destroy

tf-output:
	$(TF) output -json > $(OUTPUTS_JSON)

tests: tf-output
	@test -n "$(TEST_USERNAME)" || (echo "TEST_USERNAME is required" && exit 1)
	@test -n "$(TEST_PASSWORD)" || (echo "TEST_PASSWORD is required" && exit 1)
	@test -s "$(OUTPUTS_JSON)" || (echo "Missing or empty $(OUTPUTS_JSON)" && exit 1)
	@mkdir -p "$(TEST_RESULTS_DIR)"
	@docker run --rm \
		-i \
		-v "$(PWD):/work" \
		-w /work \
		-e AWS_PROFILE \
		-e AWS_REGION \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e AWS_CONFIG_FILE=/.aws/config \
		-e AWS_SHARED_CREDENTIALS_FILE=/.aws/credentials \
		-e AWS_SDK_LOAD_CONFIG=1 \
		-e TEST_USERNAME \
		-e TEST_PASSWORD \
		-e OUTPUTS_JSON \
		-v "$(HOME)/.aws:/.aws:ro" \
		python:3.11-slim \
		/bin/sh -c "pip install --no-cache-dir -r tests/requirements.txt && pytest -s -vv tests --outputs-json '$(OUTPUTS_JSON)' --auth-region '$(AWS_REGION)' --junitxml '$(TEST_RESULTS_DIR)/pytest.xml'"
