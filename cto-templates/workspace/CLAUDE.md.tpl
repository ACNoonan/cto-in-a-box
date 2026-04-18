# {{PROJECT_NAME}} Workspace Handbook

This workspace is the coordination layer for `{{PROJECT_NAME}}`.

## Purpose

The parent workspace exists to make cross-repo engineering predictable:

- shared branch strategy
- shared deployment expectations
- shared ops scripts
- shared agent rules
- shared debugging workflows

## Layout

{{REPO_BULLETS}}

## Default Conventions

- Region: `{{AWS_REGION}}`
- Environments: `{{ENVIRONMENTS_INLINE}}`
- Working branch: `{{DEV_BRANCH}}`
- Production branch: `{{PROD_BRANCH}}`

## Delivery Surfaces

- Backend services: `{{BACKEND_SERVICES_INLINE}}`
- Web apps: `{{WEB_APPS_INLINE}}`
- Mobile apps: `{{MOBILE_APPS_INLINE}}`

## Bootstrap Priorities

1. Stand up infrastructure and environment naming first.
2. Add CI/CD before relying on memory-based deploys.
3. Install operational scripts before launch pressure.
4. Add agent harnesses early so norms are encoded.
5. Add contract checks once multiple repos share APIs.

## Agent Rules Are Skeletons

`.claude/rules/` ships as empty skeletons by design. Each rule file has a self-prompt at the top listing the questions to ask the user. The first time you take on work that touches a rule's domain, fill that rule in by interviewing the user — do not invent answers. See `.claude/rules/_README.md` for the full list and the rationale.

## Operational Scripts

Templated starter scripts live in `scripts/`:

- `check-deployment.sh` — single command to answer "is prod live?"
- `ecs-logs.sh`, `waf-logs.sh`, `flow-logs.sh` — log readers for backend, WAF, and VPC
- `db-tunnel.sh`, `db-tunnel-dev.sh` — port-forward to RDS via SSM (TODOs to fill in once infra exists)
- `check-mobile-builds.sh` — EAS build + TestFlight tracker (TODOs to fill in)
- `terraform-pre-apply-guard.sh` — universal guardrails before `terraform apply`
- `prisma-check-sync.sh` — block deploy if migrations haven't been applied

Add a script the second time the team works around the same operational gap.
