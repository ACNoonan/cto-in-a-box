# 5. Default IaC is Terraform

Date: 2026-04-18
Status: Accepted

## Context

Every project needs a way to define its cloud resources in version control. The realistic options at the time of writing are:

- **Terraform** (HashiCorp, HCL). Largest provider ecosystem, stable module conventions, well-understood state model, mature CI/CD patterns, familiar to most platform engineers.
- **OpenTofu.** Community fork of Terraform after the license change. API-compatible in practice. Its long-term trajectory is promising but the ecosystem is still consolidating, and most modules and tutorials still target Terraform.
- **AWS CDK.** General-purpose programming languages (TypeScript/Python) generating CloudFormation. Powerful, but CloudFormation under the hood brings slow feedback loops, harder state recovery, and AWS-only coverage.
- **Pulumi.** Similar "real code" model with multi-cloud coverage. Smaller ecosystem than Terraform, different state service story, and less recruiting depth.

Two pressures matter for the default:

1. **Recruiting and onboarding.** A new platform engineer is most likely to have Terraform experience. Picking a less common tool taxes every hire.
2. **Review ergonomics.** HCL's declarative shape makes `terraform plan` output legible to non-authors. "Real code" IaC tools tend to produce diffs that are harder to review in a PR.

## Decision

Default the bootstrapped platform profile to Terraform for infrastructure as code. Generate a `infrastructure/terraform/` layout with path-aware GitHub Actions workflows, state in S3 + DynamoDB locking, and module conventions documented in the workspace handbook.

OpenTofu is preserved as a drop-in override for teams that have a specific reason to switch. CDK and Pulumi are override paths requiring explicit justification.

## Consequences

- The infrastructure repo has a predictable shape across projects using CTO in a Box, which makes ops scripts (`terraform-pre-apply-guard.sh`, environment promotion) meaningful and reusable.
- The team inherits a well-understood state model. Disaster recovery of Terraform state is a solved problem with existing runbooks.
- HashiCorp's license change is an acknowledged risk. The mitigation is that OpenTofu provides a practical exit path and ADR-0005 can be superseded if the ecosystem center of gravity shifts.
- "Real code" IaC benefits (loops, type checking, shared utilities) are foregone at the default. Teams that need them can override to Pulumi or CDK with eyes open.
- Contributors need Terraform familiarity to work on infrastructure changes. This is accepted because the recruiting market already optimizes for it.
