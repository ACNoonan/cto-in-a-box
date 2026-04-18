# Mobile Patterns

> **STATUS: NOT YET FILLED IN — agent, please complete this rule before touching any mobile app code or workflow.**
>
> Mobile delivery has fundamentally different mechanics than backend or web (native rebuilds, OTA updates, store review, TestFlight groups). Getting the OTA-vs-native distinction wrong is the most common way to ship a broken release.
>
> If `{{PROJECT_NAME}}` does not have a mobile app, replace this block with: `_Not applicable — no mobile surface._`
>
> **Your job:** before modifying mobile code, EAS config, or release workflow, interview the user (one short batched message).
>
> **Questions to ask:**
>
> 1. Which mobile framework? (Expo / React Native bare / native iOS / native Android.)
> 2. If Expo + EAS: which channels are in use? (development, preview, production — what does each map to?)
> 3. What is the rule for OTA updates vs full builds? (Default for Expo: native dependency change → fingerprint changes → full build required; pure JS/asset change → OTA is safe.)
> 4. How does CI detect when a native rebuild is required? (See `eas update --auto` + `expo-updates fingerprint:generate`.)
> 5. What are the bundle IDs and EAS project IDs per app?
> 6. What's the TestFlight submission flow? Which groups receive builds automatically?
> 7. Is the same CI workflow used for dev, preview, and production builds, or are they separate dispatch workflows?
> 8. What's the version-bumping policy? (Auto-increment on every build? Manual on every release?)
> 9. How are environment variables surfaced to the app? (`expo-constants` extra? `.env`? EAS Secrets?)
> 10. What's the in-simulator dev loop? (`expo start`, `start:ios`, `start:android` — confirm names.)
>
> Once answered, **replace this block** with concise rules under the headings below.

## Apps & IDs

<!-- One row per app: name, bundle ID, EAS project ID, ASC App ID -->

## Channels

<!-- development / preview / production — what each builds, what audiences see them -->

## OTA vs Native

<!-- The fingerprint check, when each path is allowed, who decides -->

## Build & Submit Workflow

<!-- The exact sequence: branch → CI → EAS build → submit → TestFlight group -->

## Versioning

<!-- Build number policy, version string policy, who bumps -->

## Environments

<!-- How env vars reach the app per channel; secrets handling -->

## Local Dev

<!-- Sim/device boot commands, Hermes vs JSC, common gotchas -->
