resource "kubectl_manifest" "gp3" {
  yaml_body = <<YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: gp3
      annotations:
        storageclass.kubernetes.io/is-default-class: 'true'
    provisioner: ebs.csi.aws.com
    parameters:
      type: gp3
    volumeBindingMode: WaitForFirstConsumer
  YAML
}
