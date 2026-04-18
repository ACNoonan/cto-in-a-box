# 6. Default TypeScript backend stack is Bun + Hono + Prisma

Date: 2026-04-18
Status: Accepted

## Context

Each backend service scaffolded by CTO in a Box needs a default runtime, web framework, and data-access layer. Leaving those choices open per-service has a compounding cost: ops scripts, CI templates, agent rules, container images, observability wiring, and onboarding all fragment if every service picks differently.

The realistic options at the time of writing:

**Runtime**

- **Node.js.** The default for TypeScript backends. Largest ecosystem and recruiting pool. Requires a transpile step (`tsx`, `ts-node`, `swc`) for TypeScript, and startup time is noticeably higher than the alternatives.
- **Bun.** Single binary that runs TypeScript directly, bundles, and includes a test runner. Startup is fast, APIs are mostly Node-compatible, and package management is dramatically quicker. Younger than Node; a small tail of native-module edge cases still exists, and some APM/observability vendors are a half-step behind.
- **Deno.** Similar pitch to Bun with a different security model. Smaller real-world adoption for server-side work; picking it commits the team to a thinner ecosystem than either Node or Bun.

**Web framework**

- **Express.** Familiar, enormous middleware catalog, but dated API, no first-class TypeScript story, and weaker ergonomics for modern patterns (streaming, Web standards Request/Response).
- **Fastify.** Fast, well-maintained, good TypeScript types. A reasonable alternative default; its middleware story is slightly heavier than Hono's.
- **Hono.** Small, fast, built on the Web standards `Request`/`Response` interfaces, runs on Bun / Node / Cloudflare Workers / Deno / Lambda without code changes. Middleware catalog is smaller than Express's but covers the common cases (auth, logging, CORS, validation).
- **NestJS.** Opinionated, decorator-heavy, imposes a specific architecture. Good for large teams that want the opinion; overkill for small services.

**Data access**

- **Prisma.** Type-safe client generated from a schema file, good migrations, broad DB support, introspection. The generated types are a significant productivity win. Costs: a codegen step in the build, a Rust-based query engine binary (cold-start overhead on Lambda), and a performance ceiling below hand-rolled SQL for complex queries.
- **Drizzle.** TypeScript-first, schema-as-code, no codegen step, lower runtime overhead, closer to SQL. Younger than Prisma; migrations tooling is still maturing.
- **Kysely.** Typed query builder, no ORM semantics, thinnest layer over the driver. Excellent for teams comfortable writing SQL; weaker story for schema management.
- **Raw SQL + driver.** Maximum control, zero abstraction tax, but every service ends up rebuilding query helpers.

The forcing function for picking a default is that variance across services carries a real tax. A project with three backends that each use a different ORM is a project where shared patterns, agent rules, and ops scripts all break down. The default should be the stack that maximizes shared leverage for a small team in the 1-to-5-service range, with clear override paths for teams with different constraints.

## Decision

Default the bootstrapped TypeScript backend profile to **Bun + Hono + Prisma**, paired with PostgreSQL as the database.

- Bun is the runtime. It runs TypeScript directly, which removes the build-step class of problems and shortens feedback loops.
- Hono is the web framework. Its Web-standards base keeps the service portable across runtimes if that ever becomes necessary, and its small surface area keeps agent rules and ops scripts readable.
- Prisma is the data-access layer. The schema file becomes a single source of truth that both humans and agents can reason about, and the generated types catch a large class of bugs at compile time.

Overrides remain available:

- **Node + Fastify + Prisma** is an approved override for teams with strict observability or vendor requirements that Bun does not yet satisfy.
- **Bun + Hono + Drizzle** is an approved override for teams that want to avoid Prisma's codegen and query engine binary, typically driven by Lambda cold-start sensitivity.
- **NestJS** and **Express** are allowed but should be documented with their own ADR when chosen.

## Consequences

- One shared backend shape across services means ops scripts, Dockerfiles, CI workflows, and agent rules can be written once and reused. This is the main payoff of picking a default at all.
- Bun's fast dev loop measurably shortens the inner edit-test cycle, which compounds over a project's lifetime.
- The team inherits Bun's youth as a risk. Mitigation: Bun is API-compatible enough with Node that migrating to Node + Fastify is a constrained, well-understood operation if needed. That escape hatch is preserved, not abstracted away.
- Prisma's codegen step adds a build-time obligation and its query engine binary adds deployment weight. Teams deploying to Lambda should evaluate whether the cold-start cost pushes them to the Drizzle override before committing.
- The default commits the project to PostgreSQL for primary data. MySQL and SQLite are supported by Prisma but are not the default. That limits multi-database ambiguity and keeps ops tooling (`db-tunnel.sh`, migration guardrails) focused.
- Recruiting: Bun and Hono are less common on résumés than Node and Express. Experience from either transfers cleanly — the concepts are the same — but onboarding plans should include a short orientation. This cost is accepted in exchange for the productivity gains.
- This decision interacts with ADR-0004 (ECS Fargate as default compute). Bun runs cleanly in a container image; nothing in this decision makes the compute default harder to hold.
