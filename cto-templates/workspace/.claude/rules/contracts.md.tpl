# Cross-Repo Contracts

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before changing any API surface that more than one repo depends on.**
>
> Contracts are how a polyrepo stays sane: every public endpoint or event is declared once, with explicit producers and consumers, and every change is checked against both sides before merge.
>
> If `{{PROJECT_NAME}}` is still single-repo or doesn't yet share APIs across repos, this rule may legitimately stay empty for a while — but **note that explicitly** rather than leaving the file ambiguous.
>
> **Your job:** if multiple repos depend on a shared API, interview the user (one short batched message) to fill this in.
>
> **Questions to ask:**
>
> 1. Which repos produce public APIs that other repos consume?
> 2. Where does the contract registry live? (e.g. `user-api/contracts/registry.json`)
> 3. What does an entry look like? (id, producer files, consumer repos + files, check commands, maturity level)
> 4. What CI step verifies producer changes don't break consumers? (e.g. typecheck the consumer repo against new types.)
> 5. What CI step detects breaking changes in public REST/GraphQL contracts? (`oasdiff`? GraphQL inspector?)
> 6. Is there codegen? (Generated TS clients, Protobuf, OpenAPI artifacts checked into the repo.)
> 7. What's the workflow when a consumer needs to be updated? (Auto-PR? Manual? Sync script?)
> 8. What's the maturity model? (e.g. "mapped" = just registered, "published" = type-checked, "frozen" = breaking change requires version bump)
> 9. Who owns the registry — the producer repo, or a separate contracts repo?
>
> Once answered, **replace this block** with concise rules under the headings below.
>
> If contracts are out of scope right now, replace this block with: `_Not yet applicable — single producer, no external consumers as of {{PROD_BRANCH}}._`

## Registry Location

<!-- Where the registry lives, the entry shape, who edits it -->

## Producer-Side Workflow

<!-- When changing a producer file, what must also change -->

## Consumer-Side Workflow

<!-- How a consumer repo gets updated when the producer changes -->

## Breaking Changes

<!-- Detection (oasdiff etc.), versioning policy, deprecation window -->

## Codegen

<!-- What's generated, where, how to refresh -->

## Maturity Levels

<!-- Mapped vs published vs frozen — what each means and the rules for each -->
