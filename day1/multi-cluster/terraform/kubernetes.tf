# # SA for secondary cluster (workload cluster)
# # Main cluster is the ArgoCD hub and doesn't need a SA to connect to itself

# ######################### SERVICE ACCOUNT ##########################
# resource "kubernetes_service_account" "argocd_secondary" {
#   provider = kubernetes.k8ssecondary
#   metadata {
#     name      = "argocd-secondary-sa"
#     namespace = "default"
#   }
# }

# ######################### SA SECRET ##########################
# resource "kubernetes_secret" "argocd-secondary-secret-sa" {
#   provider = kubernetes.k8ssecondary
#   metadata {
#     name      = "argocd-secondary-secret-sa"
#     namespace = "default"
#     annotations = {
#       "kubernetes.io/service-account.name" = "argocd-secondary-sa"
#     }
#   }
#   type                           = "kubernetes.io/service-account-token"
#   wait_for_service_account_token = true
# }

# ######################### ClusterRoleBinding ##########################

# resource "kubernetes_cluster_role_binding" "argocd-secondary" {
#   provider = kubernetes.k8ssecondary
#   metadata {
#     name = "argocd"
#   }
#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind      = "ClusterRole"
#     name      = "cluster-admin"
#   }
#   subject {
#     kind      = "ServiceAccount"
#     name      = kubernetes_service_account.argocd_secondary.metadata.0.name
#     namespace = kubernetes_service_account.argocd_secondary.metadata.0.namespace
#   }
# }

# ######################### Data Source for Secret ##########################

# data "kubernetes_secret" "argocd_secondary_secret_sa" {
#   provider = kubernetes.k8ssecondary
#   metadata {
#     name      = kubernetes_secret.argocd-secondary-secret-sa.metadata.0.name
#     namespace = kubernetes_secret.argocd-secondary-secret-sa.metadata.0.namespace
#   }
# }