# Backend Patterns

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before proceeding with the current backend task.**
>
> This file should describe the architecture and code conventions used by every backend service in `{{PROJECT_NAME}}`. It is currently a skeleton.
>
> **Your job:** before writing or modifying backend code, interview the user (one short batched message — do not stream questions one at a time) to fill this file in. Then save the file and continue.
>
> **Questions to ask in your interview:**
>
> 1. Which language / runtime do backends use? (Bun + TypeScript? Node? Go? Python?)
> 2. Which web framework? (Hono, Express, Fastify, FastAPI, Gin, etc.)
> 3. Which ORM or data access layer? (Prisma, Drizzle, sqlx, SQLAlchemy, raw SQL?)
> 4. What is the directory layout inside `src/`? (e.g. routes / services / infrastructure / middleware / lib / errors / types)
> 5. Are routes thin handlers that delegate to a service layer, or do they hold business logic?
> 6. What is the canonical error response shape? (e.g. `{ error: "message" }` vs `{ success: false, error: ... }`)
> 7. Where do domain errors live and how are they thrown? (HTTPException subclasses? error union types?)
> 8. What validation library is used and where is it required? (Zod / Valibot / Joi — required on which verbs?)
> 9. Are there idempotency requirements? (webhook dedup table, status-precondition transactions, payment unique constraints?)
> 10. Are there state machine rules? (e.g. order/booking status transitions go through a single workflow file?)
> 11. What logger is used? (avoid `console`?) Are there structured-logging conventions (request ID, user ID propagation)?
> 12. What's the convention for response shapes — paginated lists, single resources, creation responses?
>
> Once you have the answers, **replace this entire block** with concise rules under the headings below. Keep examples short. Cite real file paths from the codebase where possible.

## Architecture

<!-- Directory layout and what lives where -->

## Routing & Validation

<!-- Framework conventions, validator usage, route file size limits -->

## Error Handling

<!-- Error shape, where domain errors live, logger usage -->

## Service Layer

<!-- DI pattern, service registration, what routes may/may not import -->

## Idempotency

<!-- Webhook dedup, status preconditions, payment uniqueness -->

## State Machines

<!-- Workflow files, valid transitions, who is allowed to mutate status -->

## Type Safety & ORM Conventions

<!-- `any` policy, generated types, naming conventions, indexes -->
