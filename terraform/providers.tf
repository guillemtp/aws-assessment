provider "aws" {
  alias   = "use1"
  region  = var.primary_region
  profile = var.aws_profile
}

provider "aws" {
  alias   = "euw1"
  region  = var.secondary_region
  profile = var.aws_profile
}
