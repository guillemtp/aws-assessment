variable "project_name" {
  type = string
}

variable "candidate_email" {
  type = string
}

variable "test_user_password" {
  type      = string
  sensitive = true
}
