# Database & Migrations

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before touching schema or migration code.**
>
> **Your job:** before generating, reviewing, or applying any migration, interview the user (one short batched message) to fill this file in.
>
> **Questions to ask:**
>
> 1. Which database engine and version? (Postgres 16? RDS? Supabase? Neon? local Docker?)
> 2. Which migration tool? (Prisma migrate, Drizzle Kit, Atlas, Alembic, raw SQL files?)
> 3. Where do migration files live? (e.g. `prisma/migrations/`, `db/migrations/`)
> 4. Is there a shadow database for migration validation in CI? How is it provisioned?
> 5. What is the rule for editing migrations after they're committed? (Almost always: never. Confirm.)
> 6. How are migrations applied to dev? To prod? (Manual? Auto on deploy? Manual approval gate?)
> 7. Who is allowed to run prod migrations? (Humans only? CI? Specific service account?)
> 8. Is there a "migrations applied before deploy" check that blocks the pipeline if drift exists?
> 9. How does an engineer connect to prod DB locally for one-off scripts? (See `scripts/db-tunnel.sh`.)
> 10. Are there forbidden migration patterns? (NOT NULL adds without backfill, dropping columns in same release as code that reads them, etc.)
> 11. Are extensions required? (postgis, pgcrypto, citext, etc.)
> 12. What's the seeding / data bootstrap workflow for a fresh dev DB?
>
> Once answered, **replace this block** with concise rules under the headings below.

## Database & Tooling

<!-- Engine version, migration tool, where files live -->

## Workflow

<!-- How to author, validate, and ship a migration end-to-end -->

## Drift & Sync

<!-- Shadow DB, prisma-check-sync.sh, CI gate that blocks deploy on drift -->

## Editing Existing Migrations

<!-- The rule (almost always: don't) and the exception process -->

## Production Migrations

<!-- Who runs them, when, how to roll back -->

## Forbidden Patterns

<!-- NOT NULL without backfill, simultaneous drop+read, etc. -->

## Local Dev DB

<!-- docker-compose, seed scripts, how to reset -->
