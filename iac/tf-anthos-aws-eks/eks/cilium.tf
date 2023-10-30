################################################################################
# Cilium Helm Chart for e2e encryption with Wireguard
################################################################################

resource "helm_release" "cilium" {
  count = var.custom_addons.cilium ? 1 : 0
  name             = "cilium"
  chart            = "cilium"
  version          = "1.14.1"
  repository       = "https://helm.cilium.io/"
  description      = "Cilium Add-on"
  namespace        = "kube-system"
  create_namespace = false

  values = [
    <<-EOT
      cni:
        chainingMode: aws-cni
      enableIPv4Masquerade: false
      tunnel: disabled
      endpointRoutes:
        enabled: true
      l7Proxy: false
      encryption:
        enabled: true
        type: wireguard
    EOT
  ]

  depends_on = [
    module.eks_managed_node_group
  ]
}
