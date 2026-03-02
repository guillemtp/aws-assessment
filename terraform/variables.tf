variable "aws_profile" {
  description = "AWS CLI profile name to use. Leave null to use default credentials chain."
  type        = string
  default     = null
}

variable "primary_region" {
  description = "Primary region (must host Cognito)."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary compute region."
  type        = string
  default     = "eu-west-1"
}

variable "candidate_email" {
  description = "Candidate email used for Cognito test user and SNS payload."
  type        = string
}

variable "github_user" {
  description = "GitHub username for repo URL payload."
  type        = string
}

variable "test_user_password" {
  description = "Password for the Cognito test user. Must satisfy Cognito policy."
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Prefix for all resource names."
  type        = string
  default     = "aws-assessment"
}

variable "verification_topic_arn" {
  description = "Unleash verification SNS topic ARN."
  type        = string
  default     = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}

variable "primary_vpc_cidr" {
  description = "VPC CIDR for the primary regional stack."
  type        = string
  default     = "10.10.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "VPC CIDR for the secondary regional stack."
  type        = string
  default     = "10.20.0.0/16"
}

variable "sns_publish_enabled" {
  description = "Enable SNS publish from Greeter Lambda and ECS task. Keep false for dry run."
  type        = bool
  default     = false
}
