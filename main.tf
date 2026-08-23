locals {
  env = terraform.workspace

  # Per-workspace configuration
  # To upgrade k8s: change cluster_version for that workspace and apply
  workspace_config = {
    dev = {
      cluster_version      = "1.32"
      vpc_cidr             = "10.0.0.0/16"
      public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
      private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
      instance_type        = "t3.medium"
      desired_size         = 2
      min_size             = 1
      max_size             = 3
    }
    staging = {
      cluster_version      = "1.32"
      vpc_cidr             = "10.1.0.0/16"
      public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
      private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
      instance_type        = "t3.medium"
      desired_size         = 2
      min_size             = 1
      max_size             = 4
    }
    prod = {
      cluster_version      = "1.32"
      vpc_cidr             = "10.2.0.0/16"
      public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
      private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]
      instance_type        = "t3.large"
      desired_size         = 3
      min_size             = 2
      max_size             = 6
    }
  }

  cfg  = local.workspace_config[local.env]
  name = "${local.env}-eks"
  tags = { Environment = local.env, Project = "eks" }
}

module "vpc" {
  source = "./modules/vpc"

  name                 = "${local.name}-vpc"
  vpc_cidr             = local.cfg.vpc_cidr
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = local.cfg.public_subnet_cidrs
  private_subnet_cidrs = local.cfg.private_subnet_cidrs

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
  vpc_cidr           = local.cfg.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
  tags               = local.tags
}

module "eks_cluster" {
  source = "./modules/eks/cluster"

  name               = local.name
  cluster_version    = local.cfg.cluster_version
  cluster_role_arn   = module.iam.cluster_role_arn
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_sg_id      = module.sg.cluster_sg_id
  tags               = local.tags

  depends_on = [module.endpoints]
}

module "eks_nodegroup" {
  source = "./modules/eks/nodegroup"

  cluster_name        = module.eks_cluster.cluster_name
  cluster_version     = local.cfg.cluster_version
  node_role_arn       = module.iam.node_role_arn
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_sg_id          = module.sg.node_sg_id
  instance_type       = local.cfg.instance_type
  desired_size        = local.cfg.desired_size
  min_size            = local.cfg.min_size
  max_size            = local.cfg.max_size
  tags                = local.tags
}
