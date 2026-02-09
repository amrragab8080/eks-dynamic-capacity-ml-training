resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
  }

  triggers = {
    cluster_endpoint = var.cluster_endpoint
  }
}

resource "null_resource" "kubeflow_training_operator" {
  provisioner "local-exec" {
    command = "kubectl apply --server-side -k github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.8.0"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -k github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.8.0 || true"
  }

  depends_on = [null_resource.update_kubeconfig]
}
