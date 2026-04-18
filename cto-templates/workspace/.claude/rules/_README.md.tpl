# Agent Rules — {{PROJECT_NAME}}

This directory holds the durable engineering norms that every agent (Claude Code, Cursor, Codex) should know about when working in the `{{PROJECT_NAME}}` workspace.

## How these files are meant to be used

Each `*.md` file in this directory covers one topic (backend patterns, deployment, testing, etc.). They are **deliberately empty at bootstrap time** — the kit ships skeletons with a self-prompt at the top of each file.

The first time an agent opens one of these files for a relevant task, it should:

1. Read the self-prompt at the top of the file.
2. Stop and ask the user the questions listed there (one batch, not a stream).
3. Replace the self-prompt with the user's actual answers, written as concise rules.
4. Commit the file so the answers persist for every future session.

This is intentional. Rules baked from a generic stack guess will be ignored or contradicted in practice. Rules written from a 5-minute interview with the operator are load-bearing.

## When to add a new rule file

Add a new file (and add it to this README) the second time you see an engineer or agent stub their toe on the same class of decision. One occurrence is a one-off; two is a pattern that deserves to be encoded.

## Files

- [backend-patterns.md](backend-patterns.md) — service architecture, error shapes, validation, ORM conventions
- [database-migrations.md](database-migrations.md) — migration workflow, drift detection, dev↔prod sync
- [deployment.md](deployment.md) — branch model, who deploys what, post-deploy verification
- [testing.md](testing.md) — testing pyramid per surface (backend, web, mobile)
- [contracts.md](contracts.md) — cross-repo API contracts (when applicable)
- [mobile-patterns.md](mobile-patterns.md) — OTA vs native, EAS channels, TestFlight (mobile only)
- [infrastructure.md](infrastructure.md) — Terraform discipline, environment naming, secrets
- [operations.md](operations.md) — debugging workflow, log readers, incident response
- [security.md](security.md) — secrets handling, auth audit, credential rotation
