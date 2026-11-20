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
- `AWS_BOOTSTRAP_ROLE_ARN` (pre-existing GitHub OIDC role used only to bootstrap the foundation)
- `BUDGET_LIMIT_USD`
- `BUDGET_ALERT_EMAIL` (optional; required to enable forecast notifications)
- `EKS_PUBLIC_ACCESS_CIDRS` (a restricted JSON list; never `0.0.0.0/0`)
- `MODEL_ARTIFACT_BUCKET`
- `MODEL_ARTIFACT_KEY`
- `MODEL_ARTIFACT_SHA256` (64-character SHA-256 checksum)
- `INGRESS_HOSTNAME`
- `ACM_CERTIFICATE_ARN`

Add the `GATEWAY_HTPASSWD` value as a masked `apply` environment secret. It
must contain an nginx `htpasswd` line, for example generated with
`htpasswd -nbB operator '<password>'`.

The GitHub repository value passed to `infra\foundation` must match the
repository-ID subject used by the OIDC trust policy:
`OWNER@OWNER_ID/ephemeral-llm-eks-platform@REPOSITORY_ID`.

The model image, exact model identifier, and GPU instance allowlist must be
selected before an AWS session is started. Do not commit credentials, model
tokens, or raw prompts.

GitHub-hosted runner egress is not stable. The EKS endpoint CIDR must be
managed deliberately, or the workflows must be moved to an approved
self-hosted runner inside the VPC.

## Bootstrap order

1. Copy `infra\foundation\terraform.tfvars.example` to a local or protected
   CI variable set and set the real repository and region.
2. Configure `AWS_BOOTSTRAP_ROLE_ARN` for the protected `bootstrap` and
   `foundation-apply` environments. This role must already trust this
   repository through GitHub OIDC and have permission to create the foundation.
3. Run **Apply persistent foundation** from GitHub Actions. It creates or
   secures the state bucket, plans the foundation, and applies only the
   reviewed plan after `foundation-apply` approval.
4. Store the foundation state bucket name in `FOUNDATION_STATE_BUCKET`.
5. Review the Terraform plan for the ephemeral session.
6. Run **Start EKS session** with a lowercase session ID and an expiry no more
   than eight hours in the future.
   The session creates the ECR interface endpoints needed by its private nodes.
7. Run **Warm EKS session** to bootstrap Argo CD and activate the model.
8. Run **Verify EKS session** for the bounded validation task.
9. Run **Destroy EKS session** with `DESTROY-<session_id>`.
10. Run **Check EKS session leaks** if teardown reports an error.

Run **EKS session pipeline** manually when infrastructure is needed. It runs
ordered plan, apply, warm-up, and verification jobs, then leaves the session
running. Run **Destroy EKS session** separately when finished; it removes the
EKS cluster, NAT gateway, load balancers, and session-scoped ECR interface
endpoints while retaining the persistent ECR repository and images. Configure
required reviewers on both `apply` and `destroy`.

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
