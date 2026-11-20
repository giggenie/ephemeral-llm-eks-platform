# ephemeral-llm-eks-platform

Cost-controlled, self-hosted LLM coding infrastructure on ephemeral AWS EKS
clusters, managed with Terraform, Argo CD, and GitHub Actions.

Read `docs\architecture.md` before changing the implementation.

## Required configuration

Create a persistent, encrypted S3 bucket for Terraform state before the first
foundation run. Configure these GitHub repository or environment variables:

- `AWS_REGION`
- `PROJECT_NAME`
- `FOUNDATION_STATE_BUCKET`
- `AWS_PLAN_ROLE_ARN`
- `AWS_APPLY_ROLE_ARN`
- `AWS_DESTROY_ROLE_ARN`
- `EKS_PUBLIC_ACCESS_CIDRS` (a restricted JSON list; never `0.0.0.0/0`)

The GitHub repository value passed to `infra\foundation` must match the exact
`OWNER/ephemeral-llm-eks-platform` used by the OIDC trust policy. The intended
repository name is `ephemeral-llm-eks-platform`.

The model image, exact model identifier, and GPU instance allowlist must be
selected before an AWS session is started. Do not commit credentials, model
tokens, or raw prompts.

GitHub-hosted runner egress is not stable. The EKS endpoint CIDR must be
managed deliberately, or the workflows must be moved to an approved
self-hosted runner inside the VPC.

## Bootstrap order

1. Copy `infra\foundation\terraform.tfvars.example` to a local or protected
   CI variable set and set the real repository and region.
2. Run the persistent foundation through the protected Terraform apply workflow.
3. Store the foundation state bucket name in `FOUNDATION_STATE_BUCKET`.
4. Review the Terraform plan for the ephemeral session.
5. Run **Start EKS session** with a lowercase session ID and an expiry no more
   than eight hours in the future.
6. Run **Warm EKS session** to bootstrap Argo CD and activate the model.
7. Run **Verify EKS session** for the bounded validation task.
8. Run **Destroy EKS session** with `DESTROY-<session_id>`.
9. Run **Check EKS session leaks** if teardown reports an error.

The destroy workflow is protected and targets only the session state key. It
must never be used against the foundation state.

## Local checks

```powershell
terraform fmt -check -recursive
terraform -chdir=infra\foundation init -backend=false
terraform -chdir=infra\foundation validate
terraform -chdir=infra\session init -backend=false
terraform -chdir=infra\session validate
helm lint charts\session
helm template llm-session charts\session --set model.name=test-model --set ingress.hostname=example.invalid
```

The current chart contains a deliberately minimal gateway placeholder. Replace
it with the authenticated coding-agent gateway image and configure the model
values before running a real AWS session.
