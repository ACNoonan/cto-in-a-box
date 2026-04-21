# 4. Default compute target is ECS Fargate, not Kubernetes

Date: 2026-04-18
Status: Accepted (amended by [0008](./0008-railway-paas-before-ecs.md) — Railway is the default for Phase 1; ECS applies from Phase 2+)

## Context

Backend and automation services need a default runtime. The realistic options for a small team on AWS are:

- **ECS Fargate.** Managed container scheduler, no cluster to operate, priced per task, integrates cleanly with ALB, IAM, CloudWatch, and Secrets Manager.
- **EKS (Kubernetes).** Industry standard scheduler, largest ecosystem, but carries a significant operational footprint even in managed mode: control-plane fees, cluster upgrades, node AMI lifecycle, add-on management, RBAC, networking plugins.
- **EC2 directly.** Lower layer, more flexibility, but every team ends up rebuilding a subset of ECS or EKS in shell scripts.
- **Lambda.** Excellent for event-driven glue, weaker fit as a general-purpose runtime for stateful HTTP services that want steady-state performance and long-lived connections.

The question is which of these belongs as the default — the choice made on behalf of someone who has not yet earned the right to care. A small team with one to five backend services does not benefit enough from Kubernetes's flexibility to offset its operational tax, and pushing them into EKS tends to produce a platform team before the platform has any customers.

## Decision

Default the bootstrapped platform profile to ECS Fargate for backend and automation services. Treat EKS as an **override path**, not an alternative default, and require an explicit justification (existing Kubernetes platform team, hard multi-cloud requirements, platform-level scheduling needs, or a service footprint that materially outgrows ECS simplicity) to switch.

Lambda remains a first-class citizen for event-driven work (SQS consumers, scheduled jobs, webhook handlers) but is not the default for HTTP services.

## Consequences

- Bootstrap time is short. A new backend service reaches a running state without a cluster upgrade cadence, RBAC model, or Helm chart.
- Ops scripts (`check-deployment.sh`, `ecs-logs.sh`, `db-tunnel.sh`) can assume ECS primitives — task definitions, services, CloudWatch log groups — and remain readable.
- Teams that truly need Kubernetes pay a migration cost later. That cost is accepted as the tradeoff for not making every project pay a tax on day one.
- Vendor alignment tightens to AWS. Multi-cloud is possible but not ergonomic; teams that know they need multi-cloud should override early.
- Some hiring implications: engineers who have only used Kubernetes may need an onboarding ramp for ECS. In practice the ramp is short because ECS has fewer concepts.
