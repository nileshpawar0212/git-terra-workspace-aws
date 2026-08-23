data "aws_ssm_parameter" "bottlerocket_ami" {
  name = "/aws/service/bottlerocket/aws-k8s-${var.cluster_version}/x86_64/latest/image_id"
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.cluster_name}-ng-"
  image_id      = data.aws_ssm_parameter.bottlerocket_ami.value
  instance_type = var.instance_type

  vpc_security_group_ids = [var.node_sg_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  # Upgrade node group independently by changing ami_release_version
  # then run: terraform apply -target=module.nodegroup
  release_version = var.ami_release_version

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  # Controls rolling update behaviour during node group upgrade
  update_config {
    max_unavailable = 1
  }

  # Ignore desired_size changes (managed by autoscaler)
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = var.tags
}
