data "aws_ssm_parameter" "eks_gpu_ami" {
  name = "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2023/x86_64/nvidia/recommended/image_id"
}

resource "kubectl_manifest" "nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: gpu-nodeclass
    spec:
      amiFamily: AL2023
      amiSelectorTerms:
        - id: ${data.aws_ssm_parameter.eks_gpu_ami.value}
      role: ${split("/", var.node_role_arn)[1]}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      instanceStorePolicy: RAID0
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 200Gi
            volumeType: gp3
            iops: 3000
            throughput: 125
      userData: |
        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name}
  YAML
}

resource "kubectl_manifest" "nodepool_small" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: gpu-training-small
    spec:
      template:
        spec:
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values: ["g5.12xlarge"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          nodeClassRef:
            name: gpu-nodeclass
          taints:
            - key: nvidia.com/gpu
              effect: NoSchedule
            - key: training-size
              value: small
              effect: NoSchedule
          expireAfter: 2h
      limits:
        cpu: 1536       # 32 nodes × 48 vCPUs
        memory: 6144Gi  # 32 nodes × 192Gi
        nvidia.com/gpu: 128  # 32 nodes × 4 GPUs
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 2m
  YAML

  depends_on = [kubectl_manifest.nodeclass]
}

resource "kubectl_manifest" "nodepool_large" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: gpu-training-large
    spec:
      template:
        spec:
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values: ["g5.12xlarge"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          nodeClassRef:
            name: gpu-nodeclass
          taints:
            - key: nvidia.com/gpu
              effect: NoSchedule
            - key: training-size
              value: large
              effect: NoSchedule
          expireAfter: 2h
      limits:
        cpu: 6144        # 128 nodes × 48 vCPUs
        memory: 24576Gi  # 128 nodes × 192Gi
        nvidia.com/gpu: 512  # 128 nodes × 4 GPUs
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 2m
  YAML

  depends_on = [kubectl_manifest.nodeclass]
}
