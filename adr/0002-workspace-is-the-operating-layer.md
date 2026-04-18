# 2. The workspace is the operating layer

Date: 2026-04-18
Status: Accepted

## Context

Early-stage projects tend to spread their operational knowledge across wiki pages, Slack threads, individual repo READMEs, and tribal memory. As the project grows from one repo to several, that scatter becomes a tax on every new hire, every incident, and every agent interaction.

Two patterns were considered for where shared operating knowledge should live:

1. **Inside a designated "platform" or "ops" repo.** Familiar, but adds ceremony (a repo needs an owner, a CI pipeline, a release cadence) before the team is ready to staff it, and it puts the shared contract *inside* one of the deployable units — which inverts the dependency.
2. **At the parent workspace folder that contains all the repos, regardless of whether that folder is itself a git repo.** Closer to how engineers and agents actually navigate a project on disk, and imposes no release cadence or ownership overhead.

The forcing function is that agents (Claude Code, Cursor, Codex) and humans both need a reliable place to find: which repos exist, which branch is safe to work on, which branch deploys to production, what scripts to run after deploy, how to debug production, how migrations are handled, how agents should behave. Scattering that across repos means every consumer has to re-derive the map.

## Decision

Treat the parent workspace folder — the directory that contains the child repos — as the primary operating layer for the project. The workspace holds the handbook (`CLAUDE.md`, `AGENTS.md`), shared agent rules, the repo map, and branch/promotion conventions.

The workspace does **not** need to be a git repo itself. In most projects it will not be. Its authority comes from being the common ancestor of the deployable units, not from version control.

## Consequences

- New contributors and agents have one canonical place to orient themselves. The workspace handbook is the first file read.
- Shared invariants (branch strategy, deploy model, agent rules) do not belong to any one repo, which removes a class of ownership disputes.
- The workspace being unversioned means changes to shared rules are not automatically tracked. Teams that want stricter auditability can upgrade the workspace to a git repo later; that option is preserved.
- Tooling that expects "everything interesting is inside a git repo" needs an adjustment. The bootstrapper and agent harness already assume workspace-level files; other tools may need small configuration tweaks.
- Progressive disclosure becomes easier: workspace-wide rules at the top, repo-specific rules in each repo, domain specifics next to the code. All three layers can be read by agents in order of specificity.
