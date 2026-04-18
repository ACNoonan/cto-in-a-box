# 7. Adopt a strategic-DDD lens in the bootstrapper

Date: 2026-04-18
Status: Accepted

## Context

The bootstrapper's job is to derive a sensible repo plan and a set of scaffolded artifacts from a handful of answers about the project. The current answers are mostly mechanical: phase number, backend service names, web app names, which feature toggles to enable. Those answers produce a reasonable scaffold but they sidestep the more important question — *what is this product actually modeling?*

Two failure modes follow from sidestepping it:

1. **Repos named after vague buckets.** Teams end up with repos like `api`, `backend`, or `services` that accrete responsibilities until the seams inside them become invisible.
2. **Language drift.** Without a shared vocabulary captured anywhere, the same concept ends up with three different names across code, product conversations, and agent prompts. Every handoff pays a translation tax.

Domain-Driven Design (Evans, 2003) has two halves:

- **Strategic DDD** — ubiquitous language, subdomains (core / supporting / generic), bounded contexts, context maps. Concerned with how the problem is carved and named.
- **Tactical DDD** — aggregates, entities, value objects, domain events, repositories. Concerned with how one model is implemented in code.

The strategic half maps directly onto the questions a bootstrapper should be asking anyway. The tactical half is stack-specific, often overfit to a particular framework, and tends to produce scaffolding that gets in the way of the actual product. The two halves are independently valuable; they do not have to be adopted together.

## Decision

Adopt strategic DDD as a lens in the bootstrapper. The questionnaire and generated artifacts gain the following:

- Every phase asks for the **core domain** — its name and a one-sentence description. This is the question "what is this product trying to be excellent at?"
- Phase 1+ additionally asks for **supporting subdomains**, expected **bounded contexts**, and seed terms for the **ubiquitous language** glossary.
- The answers are persisted in the manifest under a `domain` key.
- A `DOMAIN.md` is rendered into the workspace root. It names the core domain, lists supporting subdomains and bounded contexts, and seeds the glossary. It is linked from `CLAUDE.md` and `AGENTS.md` so every agent reads from the same vocabulary.

**Tactical DDD is explicitly out of scope for the bootstrapper.** Scaffolded backend services do not ship aggregate base classes, repository interfaces, or domain-event plumbing by default. Teams that want tactical DDD can adopt it later, inside the bounded contexts they have actually defined. Forcing tactical patterns on a codebase before the strategic picture is clear is the canonical way DDD goes wrong in practice.

Phase gating is deliberate: Phase 0 only asks the core-domain question. The bigger context-map and glossary prompts are gated to Phase 1+, so a Local MVP remains minimal.

## Consequences

- The repo plan starts to reflect a model, not just a feature list. "Which repos do I need?" becomes a question about bounded contexts, which is a sharper question than "how many backends do I want?"
- Agents gain a canonical glossary to read before generating code, which measurably reduces the rate at which two files end up using different words for the same concept.
- The team picks up new vocabulary (core domain, bounded context, ubiquitous language). This has a real onboarding cost. It is accepted because the vocabulary is small, widely documented, and transfers to any future project.
- The bootstrapper's questionnaire gets longer. We mitigate this by gating the heavier questions to Phase 1+ and keeping Phase 0 to a single extra question (the core domain).
- `DOMAIN.md` becomes a new artifact the team is expected to keep roughly honest. Stale domain docs are worse than no domain docs, so the generated file is short by design and invites growth rather than front-loading ceremony.
- This decision is compatible with adopting tactical DDD later. Nothing here forecloses that path; it only decides not to walk it now.
- A companion primer ([`docs/ddd-primer.md`](../docs/ddd-primer.md)) is shipped so contributors who are new to DDD can learn the strategic half without having to buy Evans's book first.
