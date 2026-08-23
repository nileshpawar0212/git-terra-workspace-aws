variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bottlerocket_ami_release_version" {
  type        = string
  description = "Bottlerocket AMI release version for k8s 1.32 — update to upgrade nodes independently. e.g. 1.32.0-ccfb1234"
}
