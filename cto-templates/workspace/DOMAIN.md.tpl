# {{PROJECT_NAME}} Domain Model

This file is the shared vocabulary and high-level model map for `{{PROJECT_NAME}}`. Every agent, contributor, and domain expert should read from the same glossary, and that glossary lives here.

If you add a new term used in product conversations, code, or agent prompts, add it here. If two words mean the same thing, collapse them. If one word means two different things, that is a signal there are two bounded contexts hiding in one — split them explicitly.

A pragmatic primer on the concepts used below: [`docs/ddd-primer.md`](../docs/ddd-primer.md) in the CTO in a Box repo.

## Core Domain

**{{CORE_DOMAIN_NAME}}**

{{CORE_DOMAIN_DESCRIPTION}}

The core domain is what this product is trying to be excellent at. It deserves the strongest engineers, the sharpest modeling attention, and the clearest scope discipline. Anything that is not the core domain should be smaller, simpler, or bought rather than built.

## Supporting Subdomains

Necessary adjuncts that must exist to ship the core domain, but are not themselves the differentiator.

{{SUPPORTING_SUBDOMAIN_BULLETS}}

## Bounded Contexts

Each bounded context is a region where one model and one ubiquitous language apply. Outside the boundary, the same words can mean something different — and that is fine, as long as the boundary is explicit and the translation between contexts is a conscious choice, not an accident.

{{BOUNDED_CONTEXT_BULLETS}}

### Conventions for this project

- Every backend service owns at least one bounded context.
- A bounded context can live inside one service or be split across multiple — but never span two services without a documented integration pattern.
- When a new bounded context appears in a conversation, add it here before writing code for it.

### Context integration patterns in use

_Fill this in once two bounded contexts start talking to each other. Patterns to consider:_

- **Shared kernel** — small, jointly-owned model both sides agree to
- **Customer–supplier** — upstream cares about downstream's needs
- **Conformist** — downstream accepts the upstream's model as-is
- **Anti-corruption layer** — downstream translates at the boundary to protect its own model
- **Open-host service** — upstream publishes a stable protocol for many downstreams
- **Published language** — versioned shared schema (often an event contract)

## Ubiquitous Language

Terms in this glossary have one meaning within the bounded contexts that use them. If a word here starts to mean two things, it belongs in two glossary sections, one per context — not one entry with a qualifier.

{{UBIQUITOUS_LANGUAGE_BULLETS}}

### Growing the glossary

- When a domain expert uses a word you have not heard, add it here before translating it.
- When the code uses a word the business does not, that is a bug in the model even if the code compiles.
- Date the significant changes. Terms shift meaning over a product's lifetime, and a short history helps future readers understand why.

## What This File Is Not

- Not a class list. Aggregates, entities, and value objects are tactical-DDD concerns that belong near the code, not in this shared document.
- Not a requirements doc. This describes the model, not the features.
- Not locked. Domains evolve. The right cadence of updates is "whenever the vocabulary does."
