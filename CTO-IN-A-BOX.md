# CTO In A Box

Updated: 2026-04-18

This document defines a reusable operating playbook for future products.

It is not a nostalgia document and it is not a stack brochure. The goal is to capture the order of operations, the artifacts, the guardrails, and the automation that actually compounded over time so a new project can start with the right defaults instead of relearning them under pressure.

The long-term ambition is a reusable bootstrap system:

1. Ask a founder or CTO a small set of high-leverage questions.
2. Generate the correct workspace shape, repo map, rules, and CI/CD skeletons.
3. Install the same operational muscle early: logs, deploy checks, migration rules, mobile build flows, agent harnesses, and contract discipline.
4. Grow through deliberate phases instead of bolting on random maturity later.

## What This Operating Model Optimizes For

The key lesson was not "use AWS" or "use Bun" or "use Prisma."

The key lesson was that software delivery gets dramatically easier when the project has a real operating system:

- a parent workspace that explains the whole surface area
- child repos that deploy independently
- one infra repo that also owns shared operational scripts
- one common branch and promotion model
- CI that checks the right things before deploy
- post-push verification scripts that tell you what actually happened
- agent harnesses that encode norms instead of relying on memory
- contract checks that make cross-repo change safer
- mobile and web pipelines that understand the difference between JS-only and native or infrastructure changes

Most teams do not start with that full system. They reach it in layers. That is good news, because it means the system can be built intentionally from the start instead of assembled reactively.

## Core Principles

### 1. The workspace is an operating layer

A top-level folder can be more than a checkout directory. It can be the place where the whole company explains:

- what repos exist
- which branch is safe to work on
- which branch deploys to production
- what scripts to run after deploy
- how to debug production
- how database migrations are handled
- how agents should behave

This matters even if the workspace itself is not a git repo. In practice, that parent layer becomes the source of truth for humans and AI.

### 2. Mechanical enforcement beats memory

If a failure mode shows up twice, it should graduate into one of:

- a script
- a workflow
- a rule
- a contract check
- a test
- a documented promotion path

The system should reduce heroics, not celebrate them.

### 3. Progressive disclosure scales better than giant docs

Put shared invariants at the root, repo behavior in repo-local docs, and domain specifics close to the code. Agents and humans both make better decisions when the information is layered.

### 4. Every deployment surface needs its own opinionated path

Backend, web, infrastructure, and mobile should not pretend to ship the same way.

- ECS services need image, migration, and deployment-state verification.
- Terraform needs path-aware planning and pre-apply guardrails.
- Vercel apps need preview-aware E2E and environment mapping.
- Expo apps need a split between OTA updates and full store builds.

### 5. Ops scripts are product features

`check-deployment.sh`, `ecs-logs.sh`, `db-tunnel.sh`, `check-mobile-builds.sh`, WAF log readers, and audit scripts are not "extra tooling." They are what makes production survivable.

### 6. AI harnessing is part of engineering, not a sidecar

Rules, hooks, skills, contract checks, and testing guidance for Claude Code, Cursor, and Codex should be installed early enough that they shape behavior before entropy sets in.

### 7. Cross-repo changes need explicit blast-radius control

Once mobile, backend, and portals all depend on each other, "just remember to update the client" stops working. Producer files, consumer files, and required checks should be encoded.

## Recommended Default Shape

CTO in a box should be opinionated, but it should not confuse opinionated defaults with universal truth.

The cleanest mental model is:

1. pick the current maturity phase
2. apply a default platform profile
3. override that profile only when a real constraint justifies it

### Default workspace stance

These items are almost always worth having from the start:

- one non-deployable parent workspace
- shared handbook files
- shared agent rules and skills
- an explicit repo map, even if some repos do not exist yet
- canonical naming for project slug, environments, domains, and branches

These items should be phase-gated:

- active `infrastructure/`
- active `automations/`
- one or more backend repos
- one or more web repos
- mobile repos
- `internal-tools/`
- dedicated realtime or messaging service
- dedicated `platform-api`

That means the bootstrapper should derive the repo plan from phase and scope. It should not blindly stamp out a scaled-company repo set for every new project.

### Default platform profile

The default platform profile for this initiative is:

- AWS for infra and runtime
- Terraform for infrastructure as code
- ECS Fargate for backend and automation services
- PostgreSQL for primary data
- Prisma for TypeScript service data access
- Bun for TypeScript backend services and scripts
- Hono for lightweight service composition
- Next.js for portals and internal tools
- Expo for React Native apps
- GitHub Actions for CI/CD

This is not because these choices are globally perfect. It is because repeated decisions compound and platform variance carries a real tax.

### Why ECS is the default, not Kubernetes

CTO in a box should explicitly assume ECS over Kubernetes by default.

That is the right default when the goal is:

- low operational overhead
- fast bootstrap time
- clear deploy paths for a small team
- strong AWS alignment without building a platform team too early

Kubernetes should be treated as an override path, not the baseline. It becomes justified when there is a real reason such as:

- an existing Kubernetes platform team
- hard multi-cloud requirements
- platform-level scheduling or operator needs
- a service footprint that materially outgrows ECS simplicity

## The Phase Model

The right question is not "what should a mature startup stack contain?" The right question is "what is the minimum system needed for the current stage, and what should wait?"

Below is the staged model to reuse.

## Phase 0: Local MVP

### Goal

Prove the product locally with the smallest system that can still evolve cleanly.

### What exists in this phase

- parent workspace handbook
- repo map and branch strategy
- one primary domain model
- zero or one backend service
- zero or one customer-facing surface
- local database workflow or a shared dev database if needed
- shared agent harness if AI is already part of the workflow

### What should usually wait

- production-grade environment topology
- multiple backend services
- automations repo
- dedicated realtime infrastructure
- cross-repo contract machinery
- heavy E2E investment

### Strong defaults

- start with one backend and one surface at most
- model the data truth early
- make migrations and local bootstrap repeatable
- keep infrastructure conventions visible, even if the deployed environment is not active yet

### Required artifacts

- parent workspace handbook
- canonical naming conventions
- `schema.prisma`
- migration commands
- local dev database workflow
- backend architecture rule

### Exit criteria

- one primary domain can be modeled and changed safely
- the local setup is reproducible by another engineer or agent
- the repo plan for the next phase is explicit

## Phase 1: Deployed Demo

### Goal

Move from local-only progress to one shared deployed environment that stakeholders can actually use.

### What changes in this phase

- the infrastructure repo becomes active
- Terraform roots become real rather than aspirational
- the first backend service gets a real deploy path
- demo or dev environments become explicit
- secrets, domains, and environment naming stop being informal

### Strong defaults

- keep infrastructure in its own repo
- use Terraform from the beginning of deployed infrastructure
- use ECS as the default compute target for backend services
- keep the number of deployed services small

### Required artifacts

- `infrastructure/terraform/`
- environment naming conventions
- first ECS service definition and ECR naming
- first deploy workflow
- basic deploy verification path

### Exit criteria

- a stakeholder can access a shared deployed system
- infrastructure changes are reviewable
- there is one obvious command or workflow to verify a deploy

## Phase 2: Production Baseline

### Goal

Make production boring enough that releases, migrations, and debugging are procedural rather than heroic.

### What to add

- protected branch and promotion model
- separate prod and dev environments
- CI/CD with lint, typecheck, test, migration checks, and deploy gates
- Terraform guardrails and path-aware workflows
- deployment verification script
- ECS log reader
- DB tunnel workflow
- preview environments where they materially reduce risk

### Testing stance

- backend gets unit and service-level tests plus migration integrity
- web gets targeted E2E only where the business risk justifies it
- mobile gets cheap UI/state coverage first, then selective simulator coverage

### Exit criteria

- production deploy behavior is documented and branch-driven
- database or infrastructure drift blocks the pipeline instead of surprising runtime
- rollback, logs, and verification paths are standardized

## Phase 3: Scale And Expansion

### Goal

Add more surfaces, more teams, and more services without collapsing into coordination tax.

### What to add

- additional web portals
- mobile apps with clear environment mapping
- `internal-tools/` where operator workflows diverge from customer workflows
- `automations/` when background jobs or integrations become meaningful
- dedicated realtime or messaging services only when they are truly separate concerns
- cross-repo contract harnesses when multiple clients depend on shared APIs

### Strong defaults

- web portals live in a dedicated repo or monorepo
- mobile apps get their own repos and OTA-vs-native release logic
- contract checks appear when coupling becomes real, not before
- expensive E2E stays focused on high-risk flows

### Exit criteria

- new surfaces can be added without rewriting the operating model
- every app knows which environment and backend it targets
- API drift is visible in CI instead of discovered by clients later

## Phase 4: Reusable Platform

### Goal

Turn the proven operating model into a repeatable system that can be reused across products.

### What to package

- bootstrap questionnaires
- manifest schema
- repo templates
- GitHub Actions templates
- Terraform module templates
- agent harness templates
- standardized ops scripts
- starter kits for backend, web, and mobile

### Important detail

Do not optimize only for one agent product. Install a shared conceptual harness and then expose it through the formats each tool actually reads.

### Exit criteria

- the operating model can be generated intentionally instead of copied ad hoc
- agents know the branch model, repo map, deploy model, and testing norms
- repeated engineering choices become templates rather than tribal memory

## The Reusable Checklist

When starting a new project, CTO in a box should force explicit choices on the following dimensions.

### Identity

- company or product name
- slug
- current maturity phase
- likely next phase in the next 3 to 6 months
- primary domains

### Workspace shape

- parent workspace name
- child repos to create now
- child repos to defer
- single web repo vs web monorepo
- whether mobile is in scope now
- whether internal tools are in scope now

### Platform profile

- AWS region
- ECS as default compute or an approved override
- Terraform layout and state strategy
- database choice
- secret naming conventions

### Delivery surfaces

- backend API count
- web portals
- mobile apps
- automation service
- realtime service

### CI/CD

- branch strategy per repo
- required checks
- deploy targets
- preview environment stance
- mobile OTA policy
- TestFlight policy

### Testing

- backend framework
- browser E2E yes or no
- mobile testing tiers
- contract harness yes or no

### Agent harness

- Claude Code support
- Cursor support
- Codex support
- shared skills to install
- hooks to enable

## Bootstrap Output

The first bootstrap script should not immediately create cloud resources or mutate GitHub.

The first useful version should:

1. Ask the right questions about phase and scope.
2. Produce a manifest.
3. Produce a recommended repo plan for the selected phase.
4. Produce a phased checklist for the next phase transition.
5. Optionally scaffold local folders and starter docs.

That keeps the first version safe, auditable, and fast to iterate.

## Recommended Manifest Schema

The bootstrapper should capture at least:

- project name
- project slug
- current phase
- expected next phase
- aws region
- environments
- repos to create now
- repos to defer
- delivery surfaces enabled
- default platform profile
- approved architecture overrides
- backend stack choice
- web stack choice
- mobile stack choice
- database choice
- auth choice
- domains
- whether to include:
  - infrastructure repo
  - automations repo
  - internal tools repo
  - web repo
  - mobile repo(s)
  - contract harness
  - agent harness
  - preview environments
  - demo environment
  - mobile TestFlight pipelines

## What CTO In A Box Should Generate By Phase

### Phase 0: Local MVP

- `AGENTS.md`
- `CLAUDE.md`
- `.cursor/rules/`
- `.claude/settings.json`
- `.agents/skills/`
- `work/`
- first backend or surface starter

### Phase 1: Deployed Demo

- infrastructure repo scaffold
- Terraform roots
- first backend deploy workflow
- basic environment and secret conventions

### Phase 2: Production Baseline

- path-aware Terraform workflow
- backend and web CI/CD guardrails
- ops scripts starter pack
- deploy, logs, and DB access workflows

### Phase 3: Scale And Expansion

- mobile starter and release workflows
- contract harness scaffolding
- automations repo starter
- internal tools and additional surface templates

### Phase 4: Reusable Platform

- reusable questionnaires
- template libraries
- starter kits
- standardized ops and agent harness packages

## Anti-Patterns To Avoid

- creating many repos before one domain model is stable
- mixing production and working branch rules across repos without documentation
- running database migrations from agent automation against production
- treating infra scripts as afterthoughts
- adding mobile before deciding how OTA vs native build changes are distinguished
- writing one giant agent prompt instead of layered rules and skills
- allowing cross-repo contracts to remain implicit
- letting E2E suites become the first line of defense for cheap regressions

## The Ordering That Seems Best

If starting again from scratch, the recommended order is:

1. local MVP with one clear domain and one primary surface
2. first shared deployed demo on the default AWS, Terraform, and ECS path
3. production baseline with guardrails, ops scripts, and predictable deploys
4. scale and expansion only when more surfaces or teams make it necessary
5. reusable platform templates once the operating model is truly proven

This is intentionally conservative. It optimizes for compounding leverage.

## Practical Next Buildout For This Initiative

The next iterations of CTO in a box should likely be:

1. Stabilize the questionnaire and manifest format.
2. Split the playbook into templates the script can render.
3. Add local workspace scaffolding from the manifest.
4. Add repo template generation.
5. Add optional GitHub repo creation.
6. Add optional Terraform environment bootstrapping.
7. Add optional CI/CD secret and workflow generation.
8. Add optional agent harness installation for Claude Code, Cursor, and Codex.

## Short Version

Projects become repeatable platforms when their engineering systems become explicit.

CTO in a box should package that explicitness:

- the phase order
- the repo structure
- the CI/CD patterns
- the operational scripts
- the mobile and web delivery paths
- the contract discipline
- the agent harness

The point is not to automate everything on day one.

The point is to automate the parts that stop future chaos.
