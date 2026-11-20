variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "llm-sessions"
}

variable "session_id" {
  type        = string
  description = "Opaque GitHub Actions run/session identifier."
}

variable "expires_at" {
  type        = string
  description = "UTC expiration timestamp used for tags and safety checks."
}

variable "cluster_version" {
  type    = string
  default = "1.31"
}

variable "foundation_state_bucket" {
  type = string
}

variable "foundation_state_key" {
  type    = string
  default = "foundation/terraform.tfstate"
}

variable "gpu_instance_types" {
  type    = list(string)
  default = ["g4dn.xlarge"]
}

variable "on_demand_fallback_enabled" {
  type    = bool
  default = true
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "Explicit CIDRs allowed to reach the EKS public endpoint."

  validation {
    condition     = length(var.eks_public_access_cidrs) > 0 && !contains(var.eks_public_access_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one restricted EKS API CIDR; 0.0.0.0/0 is prohibited."
  }
}
