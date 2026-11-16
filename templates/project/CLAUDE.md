# {{PROJECT_NAME}}

## What this is

<!-- One paragraph: what we're building, who it's for, what "done" looks like. -->

## Stack

<!-- e.g. Next.js + Tailwind, deployed on Vercel. Fill in once chosen. -->

## Folders

- `docs/`: notes, specs, research
- `design/mockups/`: screenshots and mockups to build from
- `ai/`: prompts and notes for AI tools
- `finances/`: costs and receipts (ignored by git, never commit it)
- `STATUS.md`: where things stand. Read it at the start of a session.

## Rules

- Start each session by reading `STATUS.md`. At the end, update
  "Where I left off" and "Next step".
- Work in small steps and commit after each one that works.
- Never put API keys or passwords in code. Use `.env` (git ignores it) and
  keep `.env.example` up to date with the key names only.
- Before adding a paid service or package with a cost, ask first and add it to
  the costs table in `STATUS.md`.
- Explain changes in plain English. I'm learning.
- Framework starters (Next.js, Vite) expect an empty folder. Set them up in
  this folder while keeping the existing files.
