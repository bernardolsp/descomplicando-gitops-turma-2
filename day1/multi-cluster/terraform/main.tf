module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "aula-ao-vivo"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = "main-eks-lab"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "this" {
  for_each                                 = toset(["aula-ao-vivo"])
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "21.10.1"
  name                                     = "${each.key}-eks-lab"
  kubernetes_version                       = "1.34"
  enable_cluster_creator_admin_permissions = true
  endpoint_public_access                   = true
  endpoint_private_access                  = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    eks_nodes = {
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      instance_types = ["t3.medium", "t3a.medium"]
    }
  }

  # Allow ALB to communicate with pods
  node_security_group_additional_rules = {
    ingress_alb_to_nodes = {
      type        = "ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = module.vpc.public_subnets_cidr_blocks
      description = "Allow ALB to reach nodes on all ports"
    }
  }

  addons = {
    coredns                = {
      before_compute = true
    },
    kube-proxy             = {},
    vpc-cni                = {
      before_compute = true
    },
    eks-pod-identity-agent = {
      before_compute = true
    },
  }

  tags = {
    Terraform   = "true"
    Environment = each.key
    # Add Karpenter discovery tag for main cluster
    "karpenter.sh/discovery" = each.key == "aula-ao-vivo" ? "${each.key}-eks-lab" : ""
  }

}

module "eks_blueprints_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"

  cluster_name      = module.this["aula-ao-vivo"].cluster_name
  cluster_endpoint  = module.this["aula-ao-vivo"].cluster_endpoint
  cluster_version   = module.this["aula-ao-vivo"].cluster_version
  oidc_provider_arn = module.this["aula-ao-vivo"].oidc_provider_arn
  enable_metrics_server                  = true
  enable_aws_load_balancer_controller    = true
  enable_karpenter                       = false  # Disable to remove old Karpenter resources
  aws_load_balancer_controller = {
    set = [
      {
        name = "vpcId"
        value = module.vpc.vpc_id
      }
    ]
  }
  tags = {
    Environment = "dev"
  }
}

# Karpenter module - better than blueprints-addons
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.10.1"

  cluster_name = module.this["aula-ao-vivo"].cluster_name

  # Use Pod Identity for authentication
  create_pod_identity_association = true
  namespace                       = "karpenter"
  service_account                 = "karpenter"

  # IAM role for Karpenter controller
  iam_role_name            = "KarpenterController-aula-ao-vivo"
  iam_role_use_name_prefix = false

  # IAM role for Karpenter nodes
  create_node_iam_role          = true
  node_iam_role_name            = "KarpenterNodeRole-aula-ao-vivo"
  node_iam_role_use_name_prefix = false

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "dev"
  }
}

# Karpenter Helm Release
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.8.2"
  wait             = false

  values = [
    <<-EOT
    settings:
      clusterName: ${module.this["aula-ao-vivo"].cluster_name}
      clusterEndpoint: ${module.this["aula-ao-vivo"].cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    serviceAccount:
      name: ${module.karpenter.service_account}
    EOT
  ]

  depends_on = [
    module.karpenter
  ]
}



# resource "aws_secretsmanager_secret" "argocd_cluster_secret_secondary" {
#   name = "argocd-cluster-secret-secondary-lab-2"
# }

####################### Secret Version #########################

# resource "aws_secretsmanager_secret_version" "argocd_cluster_secondary_secret_version" {
#   secret_id = aws_secretsmanager_secret.argocd_cluster_secret_secondary.id
#   secret_string = jsonencode({
#     config = {
#       bearerToken = nonsensitive(data.kubernetes_secret.argocd_secondary_secret_sa.data.token)
#       tlsClientConfig = {
#         caData   = base64encode(nonsensitive(data.kubernetes_secret.argocd_secondary_secret_sa.data["ca.crt"]))
#         insecure = false
#       }
#     }
#     name   = module.this["secondary"].cluster_name
#     server = module.this["secondary"].cluster_endpoint
#   })
# }