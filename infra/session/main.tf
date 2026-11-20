data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket = var.foundation_state_bucket
    key    = var.foundation_state_key
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "session" {
  allocation_id = aws_eip.nat.id
  subnet_id     = data.terraform_remote_state.foundation.outputs.public_subnet_ids[0]
}

resource "aws_route_table" "private" {
  for_each = {
    for subnet_id in data.terraform_remote_state.foundation.outputs.private_subnet_ids :
    subnet_id => subnet_id
  }

  vpc_id = data.terraform_remote_state.foundation.outputs.vpc_id

  tags = {
    Project   = var.project_name
    SessionId = var.session_id
    Lifecycle = "session"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_route_table.private

  route_table_id = each.value.id
  subnet_id      = each.key
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.session.id
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  for_each = aws_route_table.private

  route_table_id  = each.value.id
  vpc_endpoint_id = data.terraform_remote_state.foundation.outputs.s3_vpc_endpoint_id
}

resource "aws_security_group" "endpoint" {
  name        = "${var.project_name}-${var.session_id}-endpoints"
  description = "Session-scoped ECR interface endpoint access."
  vpc_id      = data.terraform_remote_state.foundation.outputs.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [data.terraform_remote_state.foundation.outputs.vpc_cidr]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.terraform_remote_state.foundation.outputs.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.terraform_remote_state.foundation.outputs.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true
}

resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.session_id}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "system_nodes" {
  name = "${var.project_name}-${var.session_id}-system-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "system_nodes_worker" {
  role       = aws_iam_role.system_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "system_nodes_cni" {
  role       = aws_iam_role.system_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "system_nodes_ecr" {
  role       = aws_iam_role.system_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_eks_cluster" "session" {
  name     = "${var.project_name}-${var.session_id}"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = data.terraform_remote_state.foundation.outputs.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_vpc_endpoint.ecr_api,
    aws_vpc_endpoint.ecr_dkr
  ]
}

resource "aws_eks_access_entry" "github" {
  cluster_name      = aws_eks_cluster.session.name
  principal_arn     = data.terraform_remote_state.foundation.outputs.github_apply_role_arn
  type              = "STANDARD"
  kubernetes_groups = ["system:masters"]
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.session.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.system_nodes.arn
  subnet_ids      = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  instance_types  = ["t3.small"]
  capacity_type   = "ON_DEMAND"
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.system_nodes_worker,
    aws_iam_role_policy_attachment.system_nodes_cni,
    aws_iam_role_policy_attachment.system_nodes_ecr,
    aws_route_table_association.private,
    aws_route.private_nat,
    aws_vpc_endpoint_route_table_association.s3
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.session.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.session.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.session.name
  addon_name   = "coredns"
}

resource "helm_release" "argocd" {
  name              = "argocd"
  namespace         = "argocd"
  create_namespace  = true
  repository        = "https://argoproj.github.io/argo-helm"
  chart             = "argo-cd"
  version           = "7.7.16"
  wait              = true
  timeout           = 900
  cleanup_on_fail   = true
  dependency_update = true

  values = [yamlencode({
    server = {
      service = {
        type = "ClusterIP"
      }
    }
  })]

  depends_on = [aws_eks_node_group.system]
}

resource "helm_release" "karpenter" {
  name              = "karpenter"
  namespace         = "karpenter"
  create_namespace  = true
  repository        = "oci://public.ecr.aws/karpenter"
  chart             = "karpenter"
  version           = "1.1.1"
  wait              = true
  timeout           = 900
  dependency_update = true

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.session.name
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter.name
  }

  depends_on = [aws_eks_node_group.system]
}

resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.project_name}-${var.session_id}-interruptions"
  message_retention_seconds = 300
}

resource "aws_iam_role" "karpenter" {
  name = "${var.project_name}-${var.session_id}-karpenter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "${var.project_name}-${var.session_id}-karpenter"
  role = aws_iam_role.karpenter.name
}

resource "aws_iam_role_policy" "karpenter" {
  role = aws_iam_role.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateFleet",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:Describe*",
        "ec2:CreateTags",
        "ec2:DeleteLaunchTemplate",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateLaunchTemplateVersion",
        "iam:PassRole",
        "ssm:GetParameter",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = "*"
    }]
  })
}

resource "kubernetes_namespace" "session" {
  metadata {
    name = "llm-session"
  }

  depends_on = [helm_release.argocd]
}

locals {
  model_artifact_bucket = var.model_artifact_bucket != "" ? var.model_artifact_bucket : data.terraform_remote_state.foundation.outputs.artifacts_bucket
}
