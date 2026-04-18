# Security

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before touching auth code, secrets, IAM, or anything that handles credentials.**
>
> **Your job:** before generating, refactoring, or reviewing any security-adjacent change, interview the user (one short batched message).
>
> **Questions to ask:**
>
> 1. Where do secrets live in production? (AWS Secrets Manager? Vault? `.env` files mounted by ECS?)
> 2. What is the secret naming convention? (e.g. `{{PROJECT_SLUG}}/{env}/{service}/{key}`)
> 3. What's the rule for `.env` files in repos? (Forbidden in git? `.env.example` only? `.gitignore` enforced?)
> 4. Is there a secret-scanning step in CI? Pre-commit hook? Both?
> 5. What auth provider(s) are used? (Auth0, Cognito, Supabase Auth, custom JWT, Clerk, etc.)
> 6. Where does the auth audit log live? Is there a script to query it? (See `scripts/` if applicable.)
> 7. What's the credential-rotation cadence? (DB passwords, API keys, OAuth secrets.) Who runs it?
> 8. What's the rule for committing test fixtures that look like credentials? (Even fake ones can trip secret scanners.)
> 9. Are there PII handling rules? (Logging PII forbidden? Customer data scrubbed in dev DB?)
> 10. Who can access prod data? (List by role. Audit trail required for access?)
> 11. What's the policy on third-party MCP servers, browser extensions, AI tools that read code? (Especially relevant if agents are reading sensitive files.)
> 12. What's the disclosure / responsible-disclosure process if a vulnerability is found?
>
> Once answered, **replace this block** with concise rules under the headings below.

## Secrets Storage

<!-- Where secrets live, naming convention, who can read what -->

## Secret Scanning

<!-- Pre-commit + CI; what's blocked, how to handle a false positive -->

## Auth

<!-- Provider(s), token validation, session management -->

## Audit Trail

<!-- What's logged for security-sensitive actions, where to read it -->

## Credential Rotation

<!-- Cadence per credential type, who runs it -->

## PII

<!-- Logging policy, dev DB scrubbing, retention -->

## Production Data Access

<!-- Who, when, how it's audited -->

## AI / Third-Party Tools

<!-- What agents and external tools may read; sensitive paths to exclude -->
