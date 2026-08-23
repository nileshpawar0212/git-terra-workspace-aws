variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of 2 public subnet CIDRs"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of 2 private subnet CIDRs"
}

variable "azs" {
  type        = list(string)
  description = "List of 2 availability zones"
}

variable "tags" {
  type    = map(string)
  default = {}
}
