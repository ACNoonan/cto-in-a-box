# {{PROJECT_NAME}} Workspace Handbook

This workspace is the coordination layer for `{{PROJECT_NAME}}`.

## Purpose

The parent workspace exists to make cross-repo engineering predictable:

- shared branch strategy
- shared deployment expectations
- shared agent rules
- shared debugging workflows

## Layout

{{REPO_BULLETS}}

## Domain Model

Core domain: **{{CORE_DOMAIN_NAME}}**

{{CORE_DOMAIN_DESCRIPTION}}

Full bounded-context map, supporting subdomains, and the ubiquitous language glossary live in [`DOMAIN.md`](./DOMAIN.md). Agents and contributors should read from that glossary before writing code or generating prose — two files using different words for the same concept is a bug in the model.

## Default Conventions

- Deploy target: {{DEPLOY_TARGET_DESC}}
- Working branch: `{{DEV_BRANCH}}`
- Production branch: `{{PROD_BRANCH}}`

## Delivery Surfaces

- Backend services: `{{BACKEND_SERVICES_INLINE}}`
- Web apps: `{{WEB_APPS_INLINE}}`
- Mobile apps: `{{MOBILE_APPS_INLINE}}`

## Bootstrap Priorities

{{BOOTSTRAP_PRIORITIES}}

## Agent Rules Are Skeletons

`.claude/rules/` ships as empty skeletons by design. Each rule file has a self-prompt at the top listing the questions to ask the user. The first time you take on work that touches a rule's domain, fill that rule in by interviewing the user — do not invent answers. See `.claude/rules/_README.md` for the full list and the rationale.

## Operational Scripts

{{OPS_SCRIPTS_SECTION}}
