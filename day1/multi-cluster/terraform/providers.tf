provider "aws" {
  region = "us-east-1"
}

data "aws_eks_cluster_auth" "this" {
  for_each = toset(["main", "secondary"])
  name     = module.this[each.key].cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.this["main"].cluster_endpoint
    cluster_ca_certificate = base64decode(module.this["main"].cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this["main"].token
  }
}

provider "kubernetes" {
  host                   = module.this["main"].cluster_endpoint
  cluster_ca_certificate = base64decode(module.this["main"].cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this["main"].token
}

provider "kubernetes" {
  alias                  = "k8ssecondary"
  host                   = module.this["secondary"].cluster_endpoint
  cluster_ca_certificate = base64decode(module.this["secondary"].cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this["secondary"].token
}