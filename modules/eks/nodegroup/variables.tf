variable "cluster_name" {
  type = string
}

variable "node_group_name" {
  type    = string
  default = "demo-ng"
}

variable "cluster_version" {
  type    = string
  default = "1.32"
}

variable "node_role_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_sg_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
