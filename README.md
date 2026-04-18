# CTO in a Box

An opinionated operating playbook and bootstrapper for new software products.

CTO in a Box captures the order of operations, artifacts, guardrails, and automation that tend to compound over a product's lifetime — and packages them so a new project can start with the right defaults instead of relearning them under pressure.

It is two things:

1. **[`CTO-IN-A-BOX.md`](./CTO-IN-A-BOX.md)** — a written playbook describing a phase-gated operating model (local MVP → deployed demo → production baseline → scale → reusable platform).
2. **[`cto-bootstrap.sh`](./cto-bootstrap.sh)** — a zero-dependency Bash script that asks a short set of high-leverage questions, writes a manifest, and optionally scaffolds a workspace and starter templates that reflect the answers.

The first useful version of the script deliberately does **not** create cloud resources, GitHub repos, or secrets. It prints a plan and writes files you can read, commit, and iterate on.

## Who this is for

- Founders and early CTOs about to start a new product and who want a sane default shape for repos, branches, CI, and ops.
- Platform engineers who have built this operating system by hand more than once and want to stop doing that.
- Teams moving from a local MVP to a deployed demo to a real production baseline, who want the jump to be a checklist rather than an improvisation.

It is **not** a stack brochure. The opinions (AWS + Terraform + ECS, TypeScript + Bun + Hono + Prisma, Next.js, Expo, GitHub Actions) exist because repeated decisions compound and platform variance has a real tax — but they are overridable when a real constraint justifies it.

## Quickstart

Requirements:

- Bash 4+
- Python 3 (used for template rendering)

Clone and run the interactive bootstrapper:

```sh
git clone https://github.com/ACNoonan/cto-in-a-box.git
cd cto-in-a-box
./cto-bootstrap.sh
```

You'll be asked for:

- project name, slug, workspace folder name
- current maturity phase (0–4)
- AWS region, GitHub org, branch names, ECS/WAF/ECR naming
- which delivery surfaces are in scope now (backend services, web apps, mobile apps, internal tools, platform API, realtime service, automations)
- whether to include the agent harness, contract harness, preview environments, and demo environment

The script writes a manifest (`cto-bootstrap-manifest.json`) and — if you say yes — scaffolds a local workspace with a handbook, repo plan, and starter templates for infrastructure, backend, web, mobile, automation, ops scripts, and an agent harness for Claude Code / Cursor / Codex.

Nothing is pushed anywhere. Inspect, edit, commit, iterate.

## What it generates

Depending on the phase you pick, the bootstrapper generates the subset of the following that the phase calls for:

| Phase | Typical output |
| --- | --- |
| 0 — Local MVP | Parent workspace handbook, `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/`, `.claude/settings.json`, first backend or surface scaffold |
| 1 — Deployed Demo | Above, plus `infrastructure/` with Terraform roots and a first backend deploy workflow |
| 2 — Production Baseline | Path-aware Terraform workflows, backend + web CI/CD guardrails, ops scripts starter pack (`check-deployment.sh`, `ecs-logs.sh`, `db-tunnel.sh`, WAF/VPC flow log readers) |
| 3 — Scale & Expansion | Mobile scaffold + release workflows, cross-repo contract harness, `automations/`, `internal-tools/` |
| 4 — Reusable Platform | Template libraries, starter kits, standardized ops/agent harness packages |

## Repository layout

```
.
├── CTO-IN-A-BOX.md        The written playbook: principles, phases, defaults, anti-patterns.
├── cto-bootstrap.sh       Interactive bootstrapper. Writes manifest + optional scaffold.
├── adr/                   Architecture Decision Records explaining why each default exists.
└── cto-templates/
    ├── repo/              Per-repo-type workflow templates (backend, web, mobile, infra, automation).
    ├── scripts/           Ops script templates (deploy checks, logs, DB tunnel, migration checks).
    └── workspace/         Workspace-level docs: AGENTS.md, CLAUDE.md.
```

Templates use `{{VAR}}` placeholders that the script substitutes from your answers.

## Architecture Decision Records

Every significant opinion in the playbook — ECS as the default compute target, Terraform as the default IaC, phase-gated scaffolding, workspace-as-operating-layer — has a corresponding ADR in [`adr/`](./adr/). Each ADR captures the context that forced the choice, the decision itself, and the consequences of taking it.

ADRs use [Michael Nygard's original format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) and are append-only: to change a decision, write a new ADR that supersedes the old one. See [`adr/README.md`](./adr/README.md) for conventions.

## Domain-Driven Design lens

CTO in a Box uses the **strategic** half of Domain-Driven Design (Evans, 2003) as a lens for shaping the bootstrap questionnaire and the generated workspace. The questionnaire asks for the *core domain* (every phase), and — at Phase 1+ — supporting subdomains, expected bounded contexts, and seed glossary terms. The answers render into a `DOMAIN.md` at the workspace root that agents and contributors read before generating code.

Tactical DDD (aggregates, entities, value objects, repositories) is deliberately **out of scope** for the bootstrapper — see [`adr/0007-strategic-ddd-lens.md`](./adr/0007-strategic-ddd-lens.md) for the reasoning. New to DDD? Start with [`docs/ddd-primer.md`](./docs/ddd-primer.md).

## Philosophy

Four ideas do most of the work:

1. **The workspace is an operating layer.** The top-level folder, not any single repo, is the source of truth for branch strategy, deploy model, and agent behavior.
2. **Mechanical enforcement beats memory.** If a failure mode shows up twice, it graduates into a script, workflow, rule, contract check, test, or documented promotion path.
3. **Progressive disclosure scales better than giant docs.** Shared invariants at the root, repo behavior in repo-local docs, domain specifics close to the code.
4. **Every deployment surface needs its own opinionated path.** Backend, web, infra, and mobile do not ship the same way and should not pretend to.

See [`CTO-IN-A-BOX.md`](./CTO-IN-A-BOX.md) for the long form.

## Status

Early and opinionated. The script is intentionally conservative — it stops short of creating cloud resources or mutating GitHub. Feedback, issues, and PRs that sharpen the defaults (or cleanly expose override paths) are welcome.

Things on the near-term list:

- stabilizing the questionnaire and manifest schema
- splitting the playbook further into templates the script can render
- optional GitHub repo creation
- optional Terraform environment bootstrapping
- optional CI/CD secret and workflow generation
- optional agent harness installation

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE) © 2026 Adam Noonan
