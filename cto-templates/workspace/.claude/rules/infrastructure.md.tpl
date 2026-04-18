# Infrastructure

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before changing any Terraform, IAM, or AWS resource.**
>
> **Your job:** before editing infrastructure code, interview the user (one short batched message).
>
> **Questions to ask:**
>
> 1. Which cloud provider(s) and region(s)? (AWS `{{AWS_REGION}}` is the default; confirm.)
> 2. Which IaC tool? (Terraform, OpenTofu, Pulumi, CDK.) Where do roots live? (`infrastructure/terraform/`?)
> 3. What's the environment naming convention? (e.g. `prod`, `dev`, `demo` — used as suffix? prefix? tag?)
> 4. Where does the Terraform state live? (S3 backend with DynamoDB lock? Terraform Cloud?)
> 5. Are there separate state files per environment? Per service?
> 6. What's the apply workflow? (Plan on PR, apply on merge to `{{PROD_BRANCH}}`? Manual `terraform apply`? Manual approval gate?)
> 7. What are the pre-apply guardrails? (See `scripts/terraform-pre-apply-guard.sh`.) Add anything project-specific here.
> 8. What naming conventions are enforced? (Resources prefixed with env? Tags required: `Project`, `Env`, `Owner`, `CostCenter`?)
> 9. Where do secrets live? (AWS Secrets Manager naming convention, e.g. `{{PROJECT_SLUG}}/{env}/{service}/{key}`.)
> 10. Who can `terraform apply` to prod? (Humans only? CI? Specific role?)
> 11. What requires manual review even when CI is green? (IAM changes, security group rules, RDS, anything destructive.)
> 12. Are there modules that should never be touched without a sign-off? (Audit logging, billing, networking core.)
>
> Once answered, **replace this block** with concise rules under the headings below.

## Cloud & Tooling

<!-- Provider, region(s), IaC tool, state backend -->

## Environments

<!-- prod / dev / demo / preview — naming, separation, who can deploy each -->

## Apply Workflow

<!-- Plan on PR, apply on merge, who can apply, manual vs CI -->

## Pre-Apply Guardrails

<!-- Reference scripts/terraform-pre-apply-guard.sh; list project-specific checks -->

## Naming & Tagging

<!-- Resource naming convention, required tags, enforcement mechanism -->

## Secrets

<!-- Secrets Manager naming, who can read what, rotation policy -->

## High-Risk Modules

<!-- Modules requiring extra review (IAM, networking, audit) -->
