name: Deploy Automations

on:
  push:
    branches: [{{PROD_BRANCH}}]
  workflow_dispatch:

env:
  AWS_REGION: {{AWS_REGION}}
  SERVICE_NAME: automations

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
          if git rev-parse HEAD~1 >/dev/null 2>&1; then
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

  deploy:
    needs: [secret-scan, repo-contract]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: TODO ECS deploy
        run: |
          echo "Hook up image build and ECS deployment for the automations service."
