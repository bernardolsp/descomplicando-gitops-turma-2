provider "aws" {
  region = "us-east-1"
}

data "aws_eks_cluster_auth" "this" {
  for_each = toset(["aula-ao-vivo"])
  name     = module.this[each.key].cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.this["aula-ao-vivo"].cluster_endpoint
    cluster_ca_certificate = base64decode(module.this["aula-ao-vivo"].cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this["aula-ao-vivo"].token
  }
}

provider "kubernetes" {
  host                   = module.this["aula-ao-vivo"].cluster_endpoint
  cluster_ca_certificate = base64decode(module.this["aula-ao-vivo"].cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this["aula-ao-vivo"].token
}

provider "kubernetes" {
  alias                  = "k8ssecondary"
  host                   = module.this["secondary"].cluster_endpoint
  cluster_ca_certificate = base64decode(module.this["secondary"].cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this["secondary"].token
}