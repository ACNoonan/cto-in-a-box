# {{PROJECT_NAME}} Workspace

`{{WORKSPACE_NAME}}/` is a parent workspace, not a single deployable repository. Each child directory with its own CI/CD configuration should be treated as an independent repo.

## Repositories

{{REPO_BULLETS}}

## Branch Model

- Default working branch: `{{DEV_BRANCH}}`
- Default production branch: `{{PROD_BRANCH}}`
- Promote by fast-forward merge only
- Do not create feature branches unless there is a strong reason

## Operating Rules

- Run git commands inside the correct child repo, never from the workspace root.
- Keep shared ops scripts in `infrastructure/scripts/`.
- Treat the parent workspace as the system of record for cross-repo conventions.
- Keep agent guidance at the workspace root and deep domain guidance closer to code.

## CI/CD Expectations

- Backend repos: lint, typecheck, tests, and deploy pipelines
- Infrastructure repo: path-aware Terraform workflow
- Web repos: preview and production deployment path
- Mobile repos: PR validation plus manual EAS/TestFlight workflows

## Agent Harness

If enabled, this workspace uses:

- `.claude/rules/` — durable engineering norms (see `.claude/rules/_README.md`)
- `.cursor/rules/` — Cursor-format guidance
- `.claude/settings.json` and `.claude/hooks/` — Claude Code guardrails
- `.agents/skills/` — reusable skills shared across tools

**Important for agents:** every file in `.claude/rules/` ships as a skeleton with a self-prompt at the top. The first time you hit a task that touches one of these areas (backend code, migrations, deploys, tests, contracts, mobile, infra, ops, security), open the matching rule file, follow the self-prompt to interview the user, replace the prompt with the answers, and commit. Do not silently invent norms — they will not stick.
