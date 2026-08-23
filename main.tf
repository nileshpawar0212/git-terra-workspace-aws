locals {
  name = "demo-eks"
  tags = { Environment = "demo", Project = "eks" }
}

data "aws_ssm_parameter" "bottlerocket_ami_release_version" {
  name = "/aws/service/bottlerocket/aws-k8s-1.32/x86_64/latest/image_version"
}

module "vpc" {
  source = "./modules/vpc"

  name                 = "demo-eks-vpc"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

  tags = local.tags
}

module "iam" {
  source = "./modules/iam"

  name = local.name
  tags = local.tags
}

module "sg" {
  source = "./modules/sg"

  name   = local.name
  vpc_id = module.vpc.vpc_id
  tags   = local.tags
}

module "endpoints" {
  source = "./modules/endpoints"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = "10.0.0.0/16"
  private_subnet_ids = module.vpc.private_subnet_ids
  tags               = local.tags
}

module "eks_cluster" {
  source = "./modules/eks/cluster"

  name               = local.name
  cluster_version    = "1.32"
  cluster_role_arn   = module.iam.cluster_role_arn
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_sg_id      = module.sg.cluster_sg_id
  tags               = local.tags

  depends_on = [module.endpoints]
}

module "eks_nodegroup" {
  source = "./modules/eks/nodegroup"

  cluster_name        = module.eks_cluster.cluster_name
  cluster_version     = "1.32"
  ami_release_version = data.aws_ssm_parameter.bottlerocket_ami_release_version.value
  node_role_arn       = module.iam.node_role_arn
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_sg_id          = module.sg.node_sg_id
  instance_type       = "t3.medium"
  desired_size        = 2
  min_size            = 1
  max_size            = 3
  tags                = local.tags
}
