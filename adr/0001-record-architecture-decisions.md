# 1. Record architecture decisions

Date: 2026-04-18
Status: Accepted

## Context

CTO in a Box is, at its core, a pile of opinions about how to start a software product: which platform to pick, how to stage the repo layout, what belongs in CI, where operational scripts live, how agents are harnessed. Those opinions currently live as prose in `CTO-IN-A-BOX.md`. That works for a first pass, but prose erodes in two specific ways:

1. When an opinion changes, there is no obvious seam to edit — the change bleeds across paragraphs and section headers.
2. When a future project wants to override a default, there is no single artifact that captures *why* the default exists, so the override debate keeps starting from scratch.

ADRs are a well-understood remedy for both problems. They turn each significant decision into a short, append-only, reviewable markdown file.

## Decision

Adopt Architecture Decision Records, using Michael Nygard's original format: Title, Date, Status, Context, Decision, Consequences.

Records live in `adr/` at the repo root, numbered `NNNN-kebab-case-title.md` starting at `0001`. Records are append-only: to change a decision, write a new ADR that supersedes the old one and update the old one's `Status` to `Superseded by ADR-NNNN`.

MADR, Y-statements, and other heavier formats were considered. They are not adopted now because their extra structure is not earning its keep yet; the cost of writing an ADR is the main thing that kills ADR practice, and Nygard's format is the cheapest one widely recognized.

## Consequences

- Every significant opinion in the playbook gets a home where its justification is explicit and reviewable.
- Future overrides have a specific artifact to supersede, which makes override discussions shorter and more evidence-based.
- Contributors have a new obligation: non-trivial architectural changes should land with an ADR. That is a light tax on PR authors but pays back on the reader side.
- Backfilling ADRs for existing opinions is itself work. The first several records (ECS default, Terraform default, workspace-as-operating-layer, phase-gated scaffolding) are backfills dated by when they were written, not when the decisions were originally made.
- The ADR index is the directory listing. A dedicated index file is deferred until the count makes browsing the directory painful.
