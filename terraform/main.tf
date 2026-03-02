locals {
  repo_url = "https://github.com/${var.github_user}/aws-assessment"
}

module "auth" {
  source = "./modules/auth"

  providers = {
    aws = aws.use1
  }

  project_name       = var.project_name
  candidate_email    = var.candidate_email
  test_user_password = var.test_user_password
}

module "stack_use1" {
  source = "./modules/regional_stack"

  providers = {
    aws = aws.use1
  }

  project_name           = var.project_name
  region_name            = var.primary_region
  verification_topic_arn = var.verification_topic_arn
  candidate_email        = var.candidate_email
  repo_url               = local.repo_url
  vpc_cidr               = var.primary_vpc_cidr
  sns_publish_enabled    = var.sns_publish_enabled
  cognito_user_pool_id   = module.auth.user_pool_id
  cognito_user_client_id = module.auth.user_pool_client_id
  cognito_issuer         = module.auth.user_pool_issuer
}

module "stack_euw1" {
  source = "./modules/regional_stack"

  providers = {
    aws = aws.euw1
  }

  project_name           = var.project_name
  region_name            = var.secondary_region
  verification_topic_arn = var.verification_topic_arn
  candidate_email        = var.candidate_email
  repo_url               = local.repo_url
  vpc_cidr               = var.secondary_vpc_cidr
  sns_publish_enabled    = var.sns_publish_enabled
  cognito_user_pool_id   = module.auth.user_pool_id
  cognito_user_client_id = module.auth.user_pool_client_id
  cognito_issuer         = module.auth.user_pool_issuer
}
