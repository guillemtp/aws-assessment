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

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention in days (minimum 1)."
  type        = number
  default     = 1

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a valid CloudWatch Logs retention value."
  }
}
