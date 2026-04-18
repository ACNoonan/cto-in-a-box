name: Deploy

on:
  pull_request:
    branches: [{{PROD_BRANCH}}]
  workflow_dispatch:
    inputs:
      pipeline:
        description: Which pipeline to run
        required: true
        type: choice
        options:
          - dev
          - production
          - update-production

concurrency:
  group: deploy-{{APP_SLUG}}
  cancel-in-progress: true

jobs:
  lint:
    if: github.event_name == 'pull_request'
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
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: bun install --frozen-lockfile
      - run: bun run type-check

  test:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: bun install --frozen-lockfile
      - run: bun run test --runInBand

  deploy-dev:
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.pipeline == 'dev'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - uses: expo/expo-github-action@v8
        with:
          eas-version: latest
          token: ${{ secrets.EXPO_TOKEN }}
      - run: bun install --frozen-lockfile
      - name: TODO dev build or OTA
        run: echo "Add fingerprint-aware dev OTA or full build flow for {{APP_NAME}}."

  deploy-production:
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.pipeline == 'production'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - uses: expo/expo-github-action@v8
        with:
          eas-version: latest
          token: ${{ secrets.EXPO_TOKEN }}
      - run: bun install --frozen-lockfile
      - name: TODO production build
        run: echo "Add production EAS build and submit flow for {{APP_NAME}}."

  update-production:
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.pipeline == 'update-production'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - uses: expo/expo-github-action@v8
        with:
          eas-version: latest
          token: ${{ secrets.EXPO_TOKEN }}
      - run: bun install --frozen-lockfile
      - name: TODO production OTA
        run: echo "Add fingerprint-safe production OTA flow for {{APP_NAME}}."
