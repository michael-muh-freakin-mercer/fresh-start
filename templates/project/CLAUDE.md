# {{PROJECT_NAME}}

## What this is

<!-- One paragraph: what we're building, who it's for, what "done" looks like. -->

## Stack

<!-- Fill in once chosen. Default for websites: Next.js, TypeScript, Tailwind
     and shadcn/ui, deployed on Vercel. -->

## Commands

<!-- Fill in once set up, so you can check your own work. e.g.
- Dev: npm run dev
- Lint: npm run lint
- Types: npx tsc --noEmit
-->

## Folders

- `STATUS.md`: goal, where things left off, next step, services and costs,
  key names. Read it at the start of every session.
- `docs/`: notes, specs, research
- `design/mockups/`: screenshots and mockups to build from
- `ai/`: prompts and notes for AI tools
- `finances/`: costs and receipts (ignored by git, never commit it)
- `.env`: real keys (ignored by git). `.env.example` lists key names only.

This project lives in `~/projects/active/`. Don't invent a new layout or use
`~/code`. Use the helper commands (`new-project`, `bench-project`,
`unbench-project`) instead of moving folders by hand. Never read, copy or
commit anything from `~/.secrets` or `~/vault`.

## How to work

The owner decides what gets built and checks it; you do the typing. Run every
feature through the same loop:

1. **Read first.** `STATUS.md`, this file, then the code the task touches.
2. **Plan.** For anything touching more than one file, write a short plan and
   wait for approval. Skip this for tiny fixes (a color, a typo).
3. **Build one small step.** One feature per request. Do only what the plan
   says; no extra features.
4. **Verify.** Run it (dev server, lint, type check), open it in the browser,
   and check phone width (375px). Show the owner it working.
5. **Commit.** Commit with a clear message every time something works.

## Rules

- Explain what you changed and why in plain English. I'm learning.
- Never put API keys or passwords in code. Use `.env` and keep `.env.example`
  up to date. Run `gitleaks detect` before pushing if unsure.
- Before adding a paid service or package with a cost, ask first, set a
  spending cap, and add it to the costs table in `STATUS.md`.
- Ask before risky actions: deleting files, `sudo`, system config, installing
  packages, or deploying.
- Reuse existing components and installed packages before adding new ones.
- Stuck after 2 to 3 tries? Stop. List 3 possible causes, add logging to test
  each, and report back before fixing again.
- Websites: one showpiece effect per page, real copy, generous spacing.
- Framework starters (Next.js, Vite) expect an empty folder. Set them up in
  this folder while keeping the existing files.

## Before you finish

1. It runs, and you checked it on desktop and phone width.
2. No secrets in the diff; `.env` and `finances/` are not committed.
3. Work is committed with a clear message.
4. `STATUS.md` has an updated "Where I left off" and "Next step", plus any new
   service, cost or key name.
5. You told the owner, in plain English, what changed and how to see it.
