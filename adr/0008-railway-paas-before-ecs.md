# 8. Railway (PaaS) is the default for Phase 1, ECS for Phase 2+

Date: 2026-04-19
Status: Accepted
Supersedes: Partially amends 0004 (default compute is ECS Fargate)

## Context

ADR 0004 established ECS Fargate as the default compute target. That remains correct for production workloads. However, the Phase 1 ("Deployed Demo") goal is narrow: give stakeholders a shared URL they can use. Achieving that with ECS requires Terraform state backends, VPC, ALB, ECR, IAM roles, Secrets Manager, CloudWatch log groups, and a deploy workflow that pushes Docker images — a large operational surface for a team that just wants to show someone a working app.

Platform-as-a-Service providers like Railway, Render, and Fly.io reduce the Phase 1 deploy path to `git push` or a single CLI command. They handle TLS, DNS, managed Postgres, environment variables, and zero-downtime deploys without any infrastructure code. The tradeoff is less control, higher per-unit cost at scale, and vendor lock-in — all of which are acceptable at the demo stage and become unacceptable at the production stage.

The gap between "local MVP" and "deployed on AWS with Terraform and ECS" is the single largest UX cliff in the bootstrap experience. Inserting a PaaS step eliminates it.

## Decision

Make Railway the default compute target for Phase 1 (Deployed Demo). The bootstrapper generates a Railway-oriented deploy workflow and skips all AWS/ECS/Terraform prompts at Phase 1. AWS, Terraform, and ECS remain the default from Phase 2 (Production Baseline) onward — the point at which operational control, cost predictability, and infrastructure-as-code discipline justify the complexity.

Railway is the named default because it has first-class support for Dockerfiles, managed Postgres, preview environments, and a CLI that scripts well. Teams may substitute Render or Fly.io with minimal changes.

The phase model becomes:

| Phase | Compute | Infrastructure |
|-------|---------|----------------|
| 0 — Local MVP | localhost | None |
| 1 — Deployed Demo | Railway (PaaS) | None (managed by Railway) |
| 2 — Production Baseline | ECS Fargate | Terraform on AWS |
| 3 — Scale & Expansion | ECS Fargate | Terraform on AWS |
| 4 — Reusable Platform | ECS Fargate | Terraform on AWS |

## Consequences

- Phase 1 becomes dramatically simpler. A founder can go from local to a shared demo in minutes, not days.
- AWS-specific prompts (region, ECS cluster, WAF log group, VPC flow logs, ECR namespace) are deferred to Phase 2, cutting Phase 0 and Phase 1 questionnaires roughly in half.
- Teams graduate from Railway to ECS when they re-run the bootstrapper at Phase 2 or follow the documented migration path. This is an intentional migration, not an accident.
- Railway's free tier or starter plan covers most demo-stage workloads. Cost is not a meaningful factor until the production transition.
- The bootstrapper now has two deploy workflow templates for backend services: one Railway-oriented (Phase 1) and one ECS-oriented (Phase 2+). This adds template surface area but keeps each template simple.
- Ops scripts that assume ECS (ecs-logs, check-deployment, db-tunnel) are no longer generated at Phase 1, which is correct — they have no infrastructure to target.
