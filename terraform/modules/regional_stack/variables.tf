variable "project_name" {
  type = string
}

variable "region_name" {
  type = string
}

variable "verification_topic_arn" {
  type = string
}

variable "candidate_email" {
  type = string
}

variable "repo_url" {
  type = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_user_client_id" {
  type = string
}

variable "cognito_issuer" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "sns_publish_enabled" {
  type = bool
}
