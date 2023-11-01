#---------------------------------------------------------------
# Sample App for Testing
#---------------------------------------------------------------

# For some reason the example pods can't be deployed right after helm install of cilium a delay needs to be introduced. This is being investigated
resource "time_sleep" "wait_wireguard" {
  count           = var.custom_addons.example ? 1 : 0
  create_duration = "15s"

  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "server" {
  count = var.custom_addons.example ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name = "server"
      labels = {
        blog = "wireguard"
        name = "server"
      }
    }
    spec = {
      containers = [
        {
          name  = "server"
          image = "nginx"
        }
      ]
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "kubernetes.io/hostname"
          whenUnsatisfiable = "DoNotSchedule"
          labelSelector = {
            matchLabels = {
              blog = "wireguard"
            }
          }
        }
      ]
    }
  })

  depends_on = [time_sleep.wait_wireguard]
}

resource "kubectl_manifest" "service" {
  count = var.custom_addons.example ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name = "server"
    }
    spec = {
      selector = {
        name = "server"
      }
      ports = [
        {
          port = 80
        }
      ]
    }
  })
}

resource "kubectl_manifest" "client" {
  count = var.custom_addons.example ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name = "client"
      labels = {
        blog = "wireguard"
        name = "client"
      }
    }
    spec = {
      containers = [
        {
          name    = "client"
          image   = "busybox"
          command = ["watch", "wget", "server"]
        }
      ]
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "kubernetes.io/hostname"
          whenUnsatisfiable = "DoNotSchedule"
          labelSelector = {
            matchLabels = {
              blog = "wireguard"
            }
          }
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.server]
}

# Example deployment using the [pause image](https://www.ianlewis.org/en/almighty-pause-container)
# and starts with zero replicas
resource "kubectl_manifest" "inflate" {
  count     = var.custom_addons.inflate ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: inflate
    spec:
      replicas: 0
      selector:
        matchLabels:
          app: inflate
      template:
        metadata:
          labels:
            app: inflate
        spec:
          terminationGracePeriodSeconds: 0
          containers:
            - name: inflate
              image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
              resources:
                requests:
                  cpu: 1
  YAML

  #  depends_on = [
  #    kubectl_manifest.karpenter_node_template
  #  ]
}
