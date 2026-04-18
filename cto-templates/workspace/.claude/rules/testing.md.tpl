# Testing

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before adding or modifying tests.**
>
> **Your job:** before writing tests or refactoring a suite, interview the user (one short batched message). Tests written without alignment to the project's test pyramid become noise fast.
>
> **Questions to ask:**
>
> 1. Which test runners are in use, by surface? (Bun test, Vitest, Jest, Playwright, Detox, pytest, etc.)
> 2. For backend: what is "unit" vs "integration"? Does integration touch a real DB, or is the DB mocked? (If real, where does it come from — Docker? in-memory?)
> 3. For backend: which paths require contract checks before merge? (Routes, public OpenAPI, types consumed by other repos.)
> 4. For web: is there browser E2E? Against preview deploys, or local? Which user flows are covered?
> 5. For mobile: are tests tiered? (e.g. cheap RTL/Jest for UI state, Detox for high-risk flows only.) What does "high-risk flow" mean here?
> 6. What test fixtures or factories exist? Where do they live?
> 7. What's the policy on snapshot tests? On time-based tests? On flakey tests?
> 8. Are tests required to pass before merge, or just before deploy?
> 9. What's the rule for testing destructive operations? (Real cleanup? Transactional rollback? Separate test DB?)
> 10. Is there a coverage target, or is coverage informational only?
>
> Once answered, **replace this block** with concise rules under the headings below.

## Backend

<!-- Unit vs integration boundary, DB strategy, contract tests -->

## Web

<!-- Component tests, E2E, preview-aware coverage -->

## Mobile

<!-- Test tiers (mock / integration-local / integration-dev), what each tier covers -->

## Fixtures & Factories

<!-- Where they live, how to extend them -->

## Anti-Patterns

<!-- Snapshot tests for behavior, time-based assertions, suppressing flakey tests -->

## CI Enforcement

<!-- Which checks block merge; which block deploy -->
