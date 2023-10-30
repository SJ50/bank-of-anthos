resource "helm_release" "argocd" {
  count = var.custom_addons.argocd ? 1 : 0
  name             = "argo-cd"
  chart            = "argo-cd"
  version          = "4.7.21"
  #repository       = "" #defaults to bitnami?
  description      = "Install complete"
  namespace        = "argocd"
  create_namespace = false
}
