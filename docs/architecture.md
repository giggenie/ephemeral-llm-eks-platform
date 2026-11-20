# Ephemeral EKS LLM Coding Sessions

## Purpose

This project provides a disposable, self-hosted LLM coding environment on AWS.
The environment is created only for an active work session and is destroyed
afterward. The first workload is one high-reasoning coding-agent model.

The intended GitHub repository name is `ephemeral-llm-eks-platform`.

The design optimizes for:

- GitHub Actions as the only infrastructure control plane.
- No long-lived AWS credentials.
- An eight-hour maximum session lifetime.
- A target of no more than $10 per session.
- GPU Spot capacity with a strictly limited On-Demand fallback.
- Persistence only for versioned model artifacts, container images, and metrics.
- Repeatable recreation through Terraform, Helm, and Argo CD.

Argo Rollouts, multi-model serving, multi-user access, RAG, HA, and production
application onboarding are deferred.

## Session lifecycle

1. A protected GitHub Actions workflow validates the requested session inputs.
2. Terraform creates the ephemeral EKS session in the persistent VPC.
3. The workflow bootstraps Argo CD and cluster add-ons.
4. Argo CD reconciles the session Helm chart.
5. The warm-up workflow starts model hydration and waits for GPU readiness.
6. The coding agent runs the isolated validation workload.
7. Metrics and explicit artifacts are uploaded to persistent storage.
8. A scheduled or manual destroy workflow removes the session.
9. AWS leak detection verifies that no session-tagged resources remain.

The eight-hour limit applies to the complete environment lifetime, not GPU
runtime alone. GPU capacity may scale to zero while the session remains alive.

## Persistent foundation

The foundation is managed by a separate Terraform root and state key. It
survives session teardown and contains:

- One-region VPC, subnets, security groups, and required VPC endpoints.
- Versioned, encrypted S3 storage for model artifacts and compressed metrics.
- ECR repositories with immutable image tags and lifecycle policies.
- Route 53 and a reusable ACM certificate.
- GitHub OIDC provider and separate plan, apply, bootstrap, and destroy roles.
- AWS Budgets and billing alarms.
- Versioned, encrypted Terraform state with locking.
- Optional short-retention CloudWatch log groups.

Foundation resources must be tagged `lifecycle=persistent` and must never be
included in the session destroy state.

## Ephemeral session

The session is managed by a separate Terraform root and state key. It contains:

- EKS control plane and cluster security resources.
- A small system node pool.
- Karpenter and its IAM permissions.
- One GPU Spot NodePool with a maximum of one GPU node.
- One budget-gated On-Demand fallback NodePool with a maximum of one node.
- ALB, target group, and session ingress resources.
- Argo CD, Helm-managed workloads, temporary EBS volumes, and Kubernetes state.

Every session resource must include:

```text
managed-by=terraform
lifecycle=ephemeral
session-id=<opaque-run-id>
expires-at=<utc-timestamp>
```

Session state is infrastructure state only. It may be retained temporarily so
destroy can recover from interruption, then expire through an S3 lifecycle rule.
No coding-agent session state is persisted.

## GitHub Actions control plane

### Plan

`terraform-plan.yml` runs on infrastructure pull requests and validates both
Terraform roots, provider lock files, security policies, and the saved plan.
It must not apply or destroy resources.

### Apply

`terraform-apply.yml` requires a protected environment and reviewer approval.
It verifies the reviewed commit and plan hash, enforces the eight-hour expiry,
checks the session budget, and applies only the saved plan using GitHub OIDC.

Only one session apply may run at a time for this tenant.

### Warm-up

`session-warmup.yml` accepts only an allowlisted session ID and model version.
It verifies the AWS account and cluster identity, waits for Argo CD and
Karpenter, starts model hydration, waits for the GPU pod readiness probe, runs
an authenticated smoke test, and uploads timing metrics.

### Verification

`session-verify.yml` runs the representative task:

1. Implement one isolated feature.
2. Run the relevant tests.
3. Build and publish an immutable image digest.
4. Publish a versioned artifact to S3.
5. Restart the coding-agent pod.
6. Reconnect and verify the artifact and metrics.

### Destroy

`session-destroy.yml` is manually triggerable, scheduled before expiry, and
also used for failure cleanup. It requires a protected destroy environment and
an explicit confirmation string. It must:

1. Validate the session ID and AWS account.
2. Remove or disable DNS routing.
3. Delete ingress and wait for ALB cleanup.
4. Destroy only the ephemeral Terraform state.
5. Retry transient failures with bounded backoff.
6. Run independent AWS leak detection.
7. Fail loudly if GPU, EKS, NAT, ALB, ENI, EBS, or temporary IAM resources remain.

The workflow must never accept an arbitrary Terraform backend key from an
untrusted input.

## Kubernetes and model serving

Argo CD is the application reconciler. Helm charts define the gateway, model
workload, model hydration, metrics export, ingress, security context, resource
limits, and network policies.

Argo Rollouts is intentionally deferred. A normal Deployment with readiness
probes is sufficient for a single short-lived session.

Karpenter provisions GPU capacity when a GPU pod is unschedulable:

- Spot capacity is attempted first.
- The primary NodePool allows only approved GPU families.
- The maximum GPU node count is one.
- GPU nodes are tainted and labeled.
- A single On-Demand fallback is permitted only after a timeout, while budget
  remains available, and only for an allowlisted instance shape.
- Spot interruption metrics and recovery outcomes are recorded.

Model weights are immutable, checksum-verified S3 artifacts. They are hydrated
onto ephemeral local storage during the session and are not expected to survive
cluster deletion.

## Security

- GitHub Actions authenticates with AWS OIDC; no static AWS keys.
- EKS worker nodes are private.
- The public ALB is the only application ingress.
- EKS API access is restricted to approved workflow/operator paths.
- Workloads use IRSA or EKS Pod Identity with least-privilege S3 and secret access.
- Secrets are stored in AWS Secrets Manager and materialized only when needed.
- Containers run as non-root with read-only filesystems and dropped capabilities.
- Authorization headers, prompts, responses, and source code are not logged by default.
- Request size, token, timeout, concurrency, and rate limits are mandatory.
- EBS, S3, ECR, and Terraform state are encrypted.

## Cost controls

The session target is $10, with a soft alert at $7 and a hard application stop
at $9. AWS Budgets are a secondary guard because billing data can lag actual
usage. The workflow must refuse to start a session if its budget guard is active.

The primary cost drivers are EKS control-plane time, GPU runtime, NAT/data
processing, ALB time, and model/image transfer. VPC endpoints and immutable
artifact reuse should reduce repeated transfer costs.

## Acceptance criteria

- At least 8 of 10 private pilot sessions complete the representative task.
- Median successful session cost is at most $10.
- At least 95% of required artifacts, images, and metrics persist.
- No more than one manual intervention occurs across the pilot.
- The eight-hour destroy control never fails.
- Warm-up, authentication, Spot interruption, and teardown outcomes are measured.
- Post-destroy leak detection finds no session-tagged billable resources.

## Implementation sequence

1. Create and validate the persistent Terraform foundation.
2. Create the ephemeral EKS Terraform root and state handling.
3. Add Karpenter, ingress, secrets, and Argo CD bootstrap.
4. Add Helm charts for the gateway, model, hydration, metrics, and policies.
5. Add protected GitHub Actions workflows.
6. Add warm-up, validation, destroy, and leak-detection scripts.
7. Run local formatting/rendering/validation checks.
8. Run a bounded AWS smoke test only after credentials, region, model, and budget
   are explicitly configured.
