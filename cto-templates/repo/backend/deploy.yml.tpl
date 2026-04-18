name: CI and Deploy

on:
  push:
    branches: [{{PROD_BRANCH}}, {{DEV_BRANCH}}]
  pull_request:
    branches: [{{PROD_BRANCH}}]
  workflow_dispatch:

env:
  AWS_REGION: {{AWS_REGION}}
  SERVICE_NAME: {{SERVICE_NAME}}

jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - name: Scan diff
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            git fetch origin "${{ github.base_ref }}" --depth=1
            bun run secrets:check --against "origin/${{ github.base_ref }}...HEAD"
          elif git rev-parse HEAD~1 >/dev/null 2>&1; then
            bun run secrets:check --against "$(git rev-parse HEAD~1)..HEAD"
          else
            echo "No previous commit available; skipping diff secret scan."
          fi

  repo-contract:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run repo:check

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run lint

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run typecheck

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run test

  deploy-dev:
    if: github.event_name == 'push' && github.ref == 'refs/heads/{{DEV_BRANCH}}'
    needs: [secret-scan, repo-contract, lint, typecheck, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: TODO dev deploy
        run: |
          echo "Hook up AWS auth, image build, and deploy for {{SERVICE_NAME}} on {{DEV_BRANCH}}."

  deploy-prod:
    if: github.event_name == 'push' && github.ref == 'refs/heads/{{PROD_BRANCH}}'
    needs: [secret-scan, repo-contract, lint, typecheck, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: TODO prod deploy
        run: |
          echo "Hook up AWS auth, image build, and deploy for {{SERVICE_NAME}} on {{PROD_BRANCH}}."
