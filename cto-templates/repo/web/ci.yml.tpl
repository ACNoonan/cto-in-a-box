name: CI

on:
  push:
    branches: [{{DEV_BRANCH}}, {{PROD_BRANCH}}]
  pull_request:
    branches: [{{PROD_BRANCH}}]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: bun install --frozen-lockfile
      - run: bun run lint

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: bun install --frozen-lockfile
      - run: bun run typecheck

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: bun install --frozen-lockfile
      - run: bun run test

  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: bun install --frozen-lockfile
      - run: bun run build

  deploy-note:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - name: Preview or production deploy
        run: |
          echo "Connect this repo to Vercel or your web deploy target."
          echo "{{DEV_BRANCH}} should map to previews and {{PROD_BRANCH}} to production."
