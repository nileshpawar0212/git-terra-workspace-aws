terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "<your-org-name>"

    workspaces {
      tags = ["eks"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
