# A pragmatic DDD primer for CTO in a Box

Domain-Driven Design (DDD) is a 2003 book by Eric Evans and a body of practice that has grown around it. It has two halves that often get conflated:

- **Strategic DDD** — how you carve a problem into models, name those models, and decide where the seams between them live. This half is overwhelmingly about *language* and *maps*.
- **Tactical DDD** — the in-code patterns for implementing one model: aggregates, entities, value objects, domain events, repositories, factories.

This primer only teaches the strategic half. CTO in a Box adopts strategic DDD as a lens for shaping questionnaires, repo plans, and shared vocabulary. Tactical DDD is explicitly out of scope for the bootstrapper (see [`adr/0007-strategic-ddd-lens.md`](../adr/0007-strategic-ddd-lens.md) for why). If you want the tactical half later, read Vaughn Vernon's *Implementing Domain-Driven Design* (2013) — it is the closest thing to a practical manual.

## Why strategic DDD is a fit for a bootstrapper

A bootstrapper has to answer, early: *which repos should exist, and what does each one own?* Left to gut feel, that question produces either under-scaffolded projects (one repo called `app`) or over-scaffolded ones (twelve services before a single customer exists). Strategic DDD gives the question a better shape: *what is the core model, what supporting models surround it, and where are the integration seams?* The repo plan falls out of those answers.

## Core concept 1: Ubiquitous language

A **ubiquitous language** is the shared vocabulary that domain experts and engineers both use to describe the system. Every term in it maps to exactly one meaning within a given bounded context.

The test of a ubiquitous language is simple: if a product manager says "cancel an order" and an engineer says "cancel an order," do they both mean the same thing? If yes, the language is working. If one of them silently means "soft-delete the order row" and the other means "stop a pending fulfillment," the team is paying a hidden translation tax on every conversation.

Cultivating the language is a discipline, not a diagram:

- When a domain expert uses a word you have not heard, write it down and ask for the definition. Do not translate it.
- When the code uses a word the business does not use, that is a bug in the model even if the code compiles.
- When one word means two things, the model is trying to tell you there are two bounded contexts hiding inside one.

CTO in a Box captures a seed glossary at bootstrap time in `DOMAIN.md`. The glossary is meant to grow as the team learns — it is deliberately not locked down up front.

## Core concept 2: Subdomains

Evans separates subdomains into three kinds:

- **Core domain.** The thing that makes this product differentiated. If this part of the system is mediocre, the product is mediocre. Almost all strategic attention and the best engineers belong here.
- **Supporting subdomains.** Not the differentiator, but you cannot ship without them. Necessary adjuncts that should be built, but not over-built. Think: notifications, billing, audit logging *within the context of* your actual product.
- **Generic subdomains.** Problems every company in the world has. Authentication, email delivery, object storage, feature flags. You should buy or import these, not build them.

Identifying the core domain early is one of the highest-leverage things a founder or CTO can do. It answers "what am I trying to be excellent at?" which cascades into staffing, time allocation, and scope discipline.

## Core concept 3: Bounded contexts

A **bounded context** is an explicit boundary within which a particular model applies and the ubiquitous language holds. Outside the boundary, the same words can mean something different — and that is fine, as long as the boundary is explicit.

Concrete example. A single product might have three bounded contexts:

- **Ordering.** "Customer" means the person placing an order. "Order" has states like `pending`, `confirmed`, `cancelled`.
- **Fulfillment.** "Customer" means the recipient of a shipment. "Order" has states like `staged`, `picked`, `dispatched`.
- **Billing.** "Customer" means the party liable for payment. "Order" is more like an invoice line item.

Trying to force one model of `Customer` and `Order` across all three is exactly how backend code ends up with methods called `cancelOrderButOnlyIfNotYetPicked`. The boundary is doing useful work — respect it.

**Bounded contexts often, but not always, map 1:1 to services or repos.** For CTO in a Box the convention is:

- Every backend service owns at least one bounded context.
- A bounded context can live inside one service (common at Phase 0–2) or be split across multiple (sometimes necessary at Phase 3+).
- A bounded context never spans two services without an explicit integration pattern between them.

## Core concept 4: Context maps

A **context map** describes the relationships between bounded contexts. Some standard patterns:

- **Shared kernel.** Two contexts agree to share a small, jointly-owned model. Cheap but creates coupling; only use when both teams genuinely want it.
- **Customer-supplier.** The upstream context has to care about the downstream context's needs. The downstream has a voice in the upstream's backlog.
- **Conformist.** The downstream context accepts the upstream's model as-is and does not negotiate. Common when depending on a large platform or third-party API.
- **Anti-corruption layer (ACL).** The downstream context translates the upstream's model at the boundary to protect its own model. Expensive but valuable when integrating with a legacy or external system whose language you do not want to adopt.
- **Open-host service.** The upstream publishes a stable protocol for many downstreams. Public APIs usually fit here.
- **Published language.** A shared, versioned schema (e.g. an event contract) that multiple contexts translate to and from.

For a small team, the practical advice is: until you have two or more bounded contexts talking to each other, you do not need a context map. Once you do, pick the simplest pattern that fits and write it down.

## How this maps onto the bootstrapper

At bootstrap time, CTO in a Box asks:

1. **What is the core domain?** (name + one-sentence description, every phase)
2. **What supporting subdomains are in scope right now?** (Phase 1+)
3. **What bounded contexts do you expect at this phase?** (Phase 1+)
4. **What are the first glossary terms worth locking in?** (Phase 1+)

The answers are persisted to the manifest and rendered into a `DOMAIN.md` at the workspace root. That file becomes the place agents and engineers go to answer "what does this word mean in this system?"

The questions are deliberately low-ceremony. Strategic DDD at its best is a habit, not a deliverable. The goal is to start the habit, not to produce a 40-page model book before the first commit.

## Where to read more

- Eric Evans, *Domain-Driven Design: Tackling Complexity in the Heart of Software* (2003) — the original. Dense but foundational. Read the first four chapters and the strategic-design chapters; the tactical middle is safe to skim on a first pass.
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013) — the practical manual, heavier on tactical DDD.
- Vaughn Vernon, *Domain-Driven Design Distilled* (2016) — short, strategy-first, excellent entry point if the 2003 book feels like a wall.
- Eric Evans, *Domain-Driven Design Reference* (2015) — a free PDF summary of the vocabulary. Good for looking things up.

## Anti-patterns to watch for

- **Naming a bounded context after a team.** The boundary should reflect the model, not the org chart. Teams change; models are stickier.
- **Treating "microservices" as synonymous with "bounded contexts."** A bounded context is a modeling decision; a service is a deployment decision. They often align, but they are not the same word.
- **Building the context map before you have two contexts.** Premature ceremony. Wait for the friction.
- **Letting tactical DDD vocabulary (aggregates, entities, value objects) leak into conversations with the business.** Those are implementation terms. Keep them inside the engineering conversation.
- **Confusing a shared database for a shared model.** Two contexts can absolutely share storage without sharing a model, as long as each owns its own tables and does not read across the boundary.
