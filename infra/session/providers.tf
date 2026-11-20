provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Lifecycle = "ephemeral"
      SessionId = var.session_id
      ExpiresAt = var.expires_at
      Tenant    = "senraj-single-tenant"
    }
  }
}

data "aws_eks_cluster" "session" {
  name       = aws_eks_cluster.session.name
  depends_on = [aws_eks_cluster.session]
}

data "aws_eks_cluster_auth" "session" {
  name       = aws_eks_cluster.session.name
  depends_on = [aws_eks_cluster.session]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.session.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.session.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.session.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.session.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.session.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.session.token
  }
}
