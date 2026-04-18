# Operations & Debugging

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before debugging a production issue or writing a new ops script.**
>
> The kit ships a starter set of ops scripts in `scripts/` (deployment checker, ECS log reader, DB tunnel, WAF/flow log readers, mobile build tracker). This rule documents how to use them and which to reach for in which situation.
>
> **Your job:** before responding to "something is broken in prod" or before adding a new ops script, interview the user (one short batched message).
>
> **Questions to ask:**
>
> 1. What's the canonical first command when "something feels wrong in prod"? (Default suggestion: `./scripts/check-deployment.sh`.)
> 2. Which scripts in `scripts/` are wired up and which are still TODO? (Check the script headers — db-tunnel, mobile builds, etc. ship with `# TODO:` placeholders.)
> 3. Where do app logs go? (CloudWatch log group, Datadog, Logflare, etc.) Which script reads them? (`scripts/ecs-logs.sh`.)
> 4. Where do WAF and VPC flow logs land? Which script reads them? (`scripts/waf-logs.sh`, `scripts/flow-logs.sh`.)
> 5. How does an engineer get into the prod database for a one-off query? (`scripts/db-tunnel.sh`.) Who is allowed?
> 6. How does an engineer check mobile build state? (`scripts/check-mobile-builds.sh`.)
> 7. What's the on-call rotation, if any? Who gets paged for what?
> 8. What is the incident-comms channel? (Slack? Discord? PagerDuty?)
> 9. What's the post-incident process? (Blameless postmortem template, where it lives.)
> 10. When something breaks twice for the same reason, what's the rule? (Default: it graduates into a script, hook, contract check, or rule.)
>
> Once answered, **replace this block** with concise rules under the headings below.

## First Response

<!-- The single command for "is anything wrong" — usually check-deployment.sh -->

## Logs

<!-- App logs (ecs-logs.sh), WAF (waf-logs.sh), VPC flow (flow-logs.sh) — when to use which -->

## Database Access

<!-- db-tunnel.sh / db-tunnel-dev.sh — when, who, with what permissions -->

## Mobile Build State

<!-- check-mobile-builds.sh — typical workflow -->

## Incident Process

<!-- Comms channel, on-call, escalation, postmortem -->

## The "Twice Rule"

<!-- Same failure twice → encode as script, hook, rule, contract, or test -->
