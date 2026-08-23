variable "name" {
  type = string
}

variable "cluster_version" {
  type    = string
  default = "1.32"
}

variable "cluster_role_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "cluster_sg_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
