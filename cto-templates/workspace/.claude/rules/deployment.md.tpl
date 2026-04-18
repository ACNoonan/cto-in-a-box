# Deployment

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before triggering, modifying, or unblocking any deploy.**
>
> **Your job:** before pushing code, dispatching a workflow, or editing CI, interview the user (one short batched message).
>
> **Questions to ask:**
>
> 1. What is the branch model? Working branch is `{{DEV_BRANCH}}` and prod branch is `{{PROD_BRANCH}}` — is dev → prod fast-forward only? Are PRs squashed?
> 2. Which surfaces deploy from which branch? (Backend on `{{PROD_BRANCH}}`, web preview on every PR, mobile manual-only, etc.)
> 3. What does "deployed" actually mean per surface? (ECS task stable + /health 200? Vercel preview URL responds? EAS build succeeded?)
> 4. After a push, what's the canonical command to verify it's live? (Default: `./scripts/check-deployment.sh`)
> 5. Are there pre-deploy gates? (Migration integrity, secret scan, contract check, consumer typecheck.)
> 6. Are there post-deploy gates? (Smoke test, browser E2E against preview, manual sign-off.)
> 7. How are infra changes promoted? (Same branch model? Manual `terraform apply` from `{{PROD_BRANCH}}`?)
> 8. What's the rollback story per surface? (Re-deploy previous SHA? `eas update --rollback`? Manual ECS task definition revert?)
> 9. What requires the human to be sober and in front of a keyboard? (Prod migrations, IAM changes, anything destructive.)
> 10. Is there a deploy freeze policy? (Friday afternoons? Release windows? Holidays?)
>
> Once answered, **replace this block** with concise rules under the headings below.

## Branch Model

<!-- dev branch, prod branch, promotion rules, who can merge to prod -->

## Per-Surface Deploy Paths

<!-- Backend, web, mobile, infra — what triggers what -->

## Pre-Deploy Gates

<!-- Lint, typecheck, test, migration integrity, contract checks -->

## Verification

<!-- The single command an engineer runs after pushing; what "live" means -->

## Rollback

<!-- Per surface, the exact command sequence -->

## High-Risk Operations

<!-- Prod migrations, IAM, destructive ops — require explicit human approval -->

## Freeze Windows

<!-- When deploys are blocked and how to override in a true emergency -->
