---
description: Workspace structure, branch strategy, repo ownership, deploy surfaces, and operational expectations for {{PROJECT_NAME}}
---

# {{PROJECT_NAME}} Repository Structure

The `{{WORKSPACE_NAME}}/` directory is a parent workspace. Child repositories are responsible for their own CI/CD.

## Repositories

{{REPO_BULLETS}}

## Branch Strategy

- Default working branch: `{{DEV_BRANCH}}`
- Default production branch: `{{PROD_BRANCH}}`
- Promote via fast-forward only

## Delivery Model

- Backends deploy through GitHub Actions and AWS
- Infrastructure changes flow through Terraform
- Web apps should have preview and production environments
- Mobile apps should separate PR validation from store delivery

## Agent Guidance

- Use the workspace root for shared operating rules.
- Use repo-local docs for deeper domain detail.
- Keep operational scripts centralized in `infrastructure/scripts/`.
