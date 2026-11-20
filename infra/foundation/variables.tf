variable "aws_region" {
  type        = string
  description = "AWS region for the persistent foundation."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Short project identifier."
  default     = "llm-sessions"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in owner/name form."
}

variable "budget_limit_usd" {
  type        = number
  description = "Monthly AWS budget limit."
  default     = 100
}

variable "domain_name" {
  type        = string
  description = "Optional Route 53 hosted zone name."
  default     = ""
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}
