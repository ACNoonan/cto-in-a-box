# 3. Scaffold by phase, not by maximum shape

Date: 2026-04-18
Status: Accepted

## Context

A common failure mode in opinionated bootstrappers is stamping out the full shape of a mature-company codebase on day one: infrastructure repo, automations repo, internal tools repo, platform API, realtime service, contract harness, preview environments — regardless of whether the project currently has users.

This has three costs:

1. **Cognitive load.** A founder or CTO at Phase 0 now has to reason about repos and workflows they do not need yet.
2. **Premature lock-in.** Decisions get baked into scaffolding (branch names, CI gates, environment counts) before the real constraints that should drive them exist.
3. **False signal of maturity.** Having the folders of a production system without the operational muscle behind them is worse than not having them — it implies a baseline that does not actually hold.

The alternative is to derive the generated shape from the project's current maturity phase (Local MVP, Deployed Demo, Production Baseline, Scale & Expansion, Reusable Platform) and let later phases add surfaces intentionally rather than preemptively.

## Decision

The bootstrapper asks for the project's current phase and generates only the artifacts that phase calls for. Subsequent phases are reached by re-running the bootstrapper (or by explicit, documented steps) — not by having pre-generated every possible file up front.

Phase-to-output mapping (abbreviated):

- **Phase 0 — Local MVP:** workspace handbook, agent harness, first backend or surface scaffold.
- **Phase 1 — Deployed Demo:** Railway-oriented CI/deploy workflow, basic environment conventions.
- **Phase 2 — Production Baseline:** graduates to AWS + ECS; adds `infrastructure/`, Terraform roots, path-aware Terraform workflows, CI guardrails, ops scripts pack.
- **Phase 3 — Scale & Expansion:** adds mobile, contract harness, automations, internal tools as needed.
- **Phase 4 — Reusable Platform:** adds reusable template libraries and starter kits.

## Consequences

- Early-phase projects ship with less scaffolding, which is the point. The generated workspace remains small enough to read end-to-end in one sitting.
- Moving between phases is an explicit act, not a drift. That gives the team a natural moment to revisit defaults.
- The bootstrapper's surface area grows: each phase is its own code path. That complexity is accepted as the cost of not over-scaffolding.
- Users who want the full shape up front can re-run the bootstrapper at a higher phase, or manually ask for specific scaffolds. The default stays conservative.
- This decision forecloses the "one prompt emits everything" experience that some starter kits provide. That is a deliberate tradeoff: compounding leverage beats first-run impressiveness.
