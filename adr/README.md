# Architecture Decision Records

An ADR is a short, numbered, append-only markdown file that captures one significant architectural decision: the context that forced the choice, the decision itself, and the consequences (good, bad, and neutral) of taking it.

The format used here is [Michael Nygard's original](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions), chosen because:

- It is the most widely recognized ADR format. A new contributor who has ever seen one before will recognize it.
- It is short enough that the cost of writing one is small. The cost of writing one is the main thing that kills ADR practice in most teams.
- It separates *why* (Context) from *what* (Decision) from *so what* (Consequences). Those three questions are almost always the interesting ones.

Heavier formats exist — [MADR](https://adr.github.io/madr/) is popular — but we default to Nygard here. Graduate to MADR if and when we find the extra structure earns its keep.

## Conventions

- Files live in `adr/` at the repo root.
- Filenames are `NNNN-kebab-case-title.md` with a zero-padded four-digit sequence number starting at `0001`.
- Records are **append-only**. Do not rewrite history. If a decision changes, write a new ADR that supersedes the old one and update the old one's `Status` to `Superseded by ADR-NNNN`.
- Every ADR has a `Status` line. Common values: `Proposed`, `Accepted`, `Deprecated`, `Superseded by ADR-NNNN`.
- Use `adr/template.md` as the starting point.

## Why backfill existing opinions

Several of the early ADRs here are backfills — they describe decisions that were already baked into `CTO-IN-A-BOX.md` before the ADR practice existed. Backfilling is worthwhile because it:

1. Makes the *why* behind each default explicit and reviewable.
2. Gives future overrides a specific artifact to supersede, rather than a vague prose paragraph to argue with.
3. Builds the muscle for writing ADRs on new decisions going forward.

Backfilled ADRs are dated with the date they were *written* (not the date the decision was originally made). The Context section notes when the decision was made in practice.

## Index

See the `adr/` directory listing; filenames are self-describing.
