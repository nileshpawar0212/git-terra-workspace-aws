locals {
  interface_endpoints = [
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "autoscaling",
  ]
}

data "aws_region" "current" {}

resource "aws_security_group" "endpoint" {
  name        = "${var.name}-endpoint-sg"
  description = "Allow HTTPS from VPC for interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-endpoint-sg" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-${each.value}-endpoint" })
}
