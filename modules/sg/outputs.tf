output "cluster_sg_id" {
  value = aws_security_group.cluster.id
}

output "node_sg_id" {
  value = aws_security_group.node.id
}
