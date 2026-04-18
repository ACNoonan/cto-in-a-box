# Contributing to CTO in a Box

Thanks for your interest. This project is early and opinionated, so contributions that sharpen the defaults or cleanly expose override paths are especially welcome. Changes that add optionality without a real reason tend not to land.

## Ways to contribute

- **Open an issue.** Bugs in the bootstrapper, inaccuracies in the playbook, or missing templates are all fair game. Feature ideas are welcome, but please describe the concrete problem first.
- **Submit a pull request.** For anything non-trivial, open an issue first so we can agree on the shape of the change before you invest time.
- **Sharpen the playbook.** Edits to `CTO-IN-A-BOX.md` that tighten the phrasing, remove cruft, or correct outdated advice are valuable on their own.

## Development setup

Requirements:

- Bash 4+
- Python 3 (used by `cto-bootstrap.sh` for template rendering)
- [`shellcheck`](https://www.shellcheck.net/) for linting Bash

Run the bootstrapper against a scratch directory to exercise changes end to end:

```sh
./cto-bootstrap.sh
```

Point it at a throwaway workspace root when prompted so you can diff the generated output.

## Coding conventions

- **Bash**: `set -euo pipefail` at the top of every script. Prefer small, named functions over long inline blocks. Run `shellcheck` on anything you touch — CI runs it on every PR.
- **Templates**: use `{{VAR}}` placeholders. Keep templates readable as-is (no runtime-only gotchas) so someone reading the generated output can follow it without running the script.
- **Playbook**: keep the tone declarative. Describe the operating model, not the author's journey. Avoid nostalgia, brand worship, and marketing adjectives.
- **Scope discipline**: a bug fix does not need surrounding cleanup. A new capability does not need to ship with four toggles. If a change adds configurability, it should be because a real user actually needs the override.

## Commit and PR style

- Keep commits focused. Prefer several small commits over one sprawling one.
- Commit messages: imperative mood, summary line ≤ 72 chars, body explains *why* rather than *what*.
- PR descriptions: describe the problem, the change, and anything reviewers should test manually.

## What is in scope

- Improvements to the phase model, manifest schema, and questionnaire.
- New templates that fit the default platform profile (AWS + Terraform + ECS + TypeScript/Bun) or clean, documented overrides.
- Ops script templates that would otherwise be rebuilt from scratch on every project.
- Agent harness additions for Claude Code, Cursor, and Codex.

## What is probably out of scope

- Swapping the default platform profile wholesale. Overrides are welcome; replacing the baseline is a different project.
- Features that only make sense for a specific company or product.
- Templates that require private services or bespoke infrastructure not generally available.

## Reporting security issues

Please do **not** open a public issue for security problems. Email [adam@samachi.com](mailto:adam@samachi.com) with the details and a suggested fix if you have one.

