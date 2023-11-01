resource "helm_release" "ingress_internal" {
  count            = var.custom_addons.ingress_int ? 1 : 0
  name             = "ingress-nginx-internal"
  chart            = "ingress-nginx"
  version          = "4.7.1"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  description      = "A helm chart to install Ingress Nginx Internal"
  namespace        = var.ingress_internal.namespace
  create_namespace = var.ingress_internal.create_namespace
  values = [
    <<EOF
    controller:
      ingressClassByName: true
      ingressClassResource:
        name: nginx
        enabled: true
        default: true
        controllerValue: "k8s.io/ingress-nginx"
      service:
        external:
          enabled: false
        internal:
          enabled: true
          annotations:
            service.beta.kubernetes.io/aws-load-balancer-internal: "true"
            service.beta.kubernetes.io/aws-load-balancer-name: "load-balancer-internal"
            service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
            service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
            service.beta.kubernetes.io/aws-load-balancer-type: nlb
    EOF
  ]
  force_update = false
}

resource "helm_release" "ingress-public" {
  count            = var.custom_addons.ingress_ext ? 1 : 0
  name             = "ingress-nginx-public"
  chart            = "ingress-nginx"
  version          = "4.7.1"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  description      = "A helm chart to install Ingress Nginx External/Public"
  namespace        = var.ingress_external.namespace
  create_namespace = var.ingress_external.create_namespace
  values = [
    <<EOF
    controller:
      ingressClassByName: true
      ingressClassResource:
        name: nginx-public
        enabled: true
        default: false
        controllerValue: "k8s.io/ingress-nginx-public"
      ingressClass: nginx-public
      service:
        loadBalancerSourceRanges: ${var.ingress_external.source_cidrs}
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
          service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
          service.beta.kubernetes.io/aws-load-balancer-type: nlb
          service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "preserve_client_ip.enabled=true"
          # Custom names for nlb is not support by ingress-nginx controller
          # service.beta.kubernetes.io/aws-load-balancer-name: "${var.environment}-finops-${terraform.workspace}"
          # Below doesn't attach SG to NLB, leaving it wide open, currently not supported by ingress-nginx controller
          # service.beta.kubernetes.io/aws-load-balancer-security-groups: "security_group_name"
          # service.beta.kubernetes.io/aws-load-balancer-extra-security-groups: "security_group_id"
        external:
          enabled: true
    EOF
  ]
  force_update = false
}
