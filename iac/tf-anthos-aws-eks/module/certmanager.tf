data "aws_route53_zone" "selected" {
  count = var.custom_addons.cert_manager ? 1 : 0
  #Cert-manager with let's encrypt works only with public zones.
  #Let's encrypt won't be able to verify you own the domain unless it is publicly resolvable.
  name         = "${var.cert_manager.dns_zone}."
  private_zone = var.cert_manager.is_zone_private
}

data "aws_iam_policy_document" "cert_manager" {
  count = var.cert_manager.create_irsa && var.custom_addons.cert_manager ? 1 : 0
  statement {
    actions   = ["route53:GetChange", ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }

  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = [data.aws_route53_zone.selected[0].arn]
  }

  statement {
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

module "cert_manager" {
  source = "./modules/cert_manager"
  count  = var.custom_addons.cert_manager ? 1 : 0

  create_release = var.cert_manager.create_release

  # https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/Chart.template.yaml
  name             = var.cert_manager.name
  description      = var.cert_manager.description
  namespace        = var.cert_manager.namespace
  create_namespace = var.cert_manager.create_namespace
  chart            = var.cert_manager.chart
  chart_version    = var.cert_manager.chart_version
  repository       = var.cert_manager.repository
  values           = var.cert_manager.values

  postrender = var.cert_manager.postrender
  set = [
    {
      name  = "installCRDs"
      value = true
    }
  ]

  # IAM role for service account (IRSA)
  set_irsa_names                = ["serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"]
  create_role                   = var.cert_manager.create_irsa
  role_name                     = var.cert_manager.role_name
  role_name_use_prefix          = var.cert_manager.role_name_use_prefix
  role_path                     = try(var.cert_manager.role_path, "/")
  role_permissions_boundary_arn = var.cert_manager.role_permissions_boundary_arn
  role_description              = var.cert_manager.role_description
  role_policies                 = var.cert_manager.role_policies

  source_policy_documents = data.aws_iam_policy_document.cert_manager[*].json

  override_policy_documents = lookup(var.cert_manager, "override_policy_documents", [])
  policy_statements         = lookup(var.cert_manager, "policy_statements", [])
  policy_name               = try(var.cert_manager.policy_name, null)
  policy_name_use_prefix    = try(var.cert_manager.policy_name_use_prefix, true)
  policy_path               = try(var.cert_manager.policy_path, null)
  policy_description        = try(var.cert_manager.policy_description, "IAM Policy for cert-manager")

  oidc_providers = {
    this = {
      provider_arn = try(aws_iam_openid_connect_provider.oidc_provider[0].arn, null)

      # namespace is inherited from chart
      service_account = var.cert_manager.role_name
    }
  }
  tags = var.tags
}

resource "kubectl_manifest" "cluster_issuer_r53_le" {
  count = var.custom_addons.cert_manager ? 1 : 0
  #Lets encrypt issuer with route53 domain validation
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "${var.environment}-letsencrypt-r53"
    }
    spec = {
      acme = {
        email = try(var.cert_manager.email, "devops@isxfinanacial.com")
        privateKeySecretRef = {
          name = "${var.environment}-letsencrypt"
        }
        server = var.environment == "prod" ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              route53 = {
                region       = var.region
                hostedZoneID = data.aws_route53_zone.selected[0].zone_id
              }
            }
          }
        ]
      }
    }
  })
}

resource "kubectl_manifest" "cluster_issuer_nginx_le" {
  count = var.custom_addons.cert_manager ? 1 : 0
  #Lets encrypt issuer with nginx domain validation
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "${var.environment}-letsencrypt-nginx"
    }
    spec = {
      acme = {
        email = try(var.cert_manager.email, "devops@isxfinanacial.com")
        privateKeySecretRef = {
          name = "${var.environment}-letsencrypt"
        }
        server = var.environment == "prod" ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  })
}

resource "kubectl_manifest" "example_ssl_lt_r53" {
  #Test lets encrypt ssl verified by r53 record
  count = var.custom_addons.cert_le_r53 ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "example-ssl"
      namespace = "default"
    }
    spec = {
      secretName = "example-com-tls"
      issuerRef = {
        kind = "ClusterIssuer"
        name = "${var.environment}-letsencrypt-r53"
      }
      dnsNames = ["kamil-test.certmanager.${var.cert_manager.dns_zone}"]
    }
  })
}
