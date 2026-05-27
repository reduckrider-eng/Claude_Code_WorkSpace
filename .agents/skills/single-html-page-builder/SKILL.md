---
name: single-html-page-builder
description: Reusable workflow for building or updating a project-local standalone index.html page from broad user requirements. Use when Codex must gather page goals, optionally ask three multiple-choice clarification questions, delegate the single-file HTML implementation to the html-builder custom agent, and rely on configured Codex hooks for validation and auto-commit without editing hooks or project-external files.
---

# Single HTML Page Builder

Use this skill to turn a user's broad page idea into one browser-runnable `index.html` file.

## Initial Inspection

Before editing, inspect and summarize:

- OS and shell.
- Current working directory.
- Git repo root from `git rev-parse --show-toplevel`.
- Current branch and `git status --short`.
- `.codex/` structure, especially `.codex/agents/html-builder.toml` and `.codex/hooks.json`.
- Existing `index.html`, if present.
- Whether hooks appear configured. Do not call hook scripts directly.

If there is no Git repo, continue only when the user asked for file generation and clearly report that Stop hook auto-commit will likely be blocked. If `.codex/agents/html-builder.toml` is missing or the `html_builder` custom agent cannot be used, report `BLOCKED` unless the user explicitly allows local fallback implementation.

## Clarification

Identify the user's topic, purpose, target audience, desired style, supplied data, and any attached image references.

If core requirements are ambiguous, ask exactly three questions before implementation. Each question must include three concrete choices. Prefer this format:

1. Page style:
   - A. Editorial and premium
   - B. Product-like and conversion-focused
   - C. Dashboard-like and information-dense
2. Content depth:
   - A. Short overview
   - B. Balanced sections
   - C. Detailed explanatory page
3. Interaction level:
   - A. Static page
   - B. Light interactions
   - C. Rich but simple interactions

If the user does not answer and asks to proceed, use safe defaults: `1-A`, `2-B`, `3-B`. Report these assumptions in the final answer.

When an image is attached, use only layout, spacing, density, visual balance, and overall polish as reference. Do not copy the image.

## Implementation Workflow

1. Use the `html_builder` custom agent from `.codex/agents/html-builder.toml`.
2. Assign it ownership of only `index.html`.
3. Instruct it to read the existing `index.html` first if it exists.
4. Require a standalone HTML file with all CSS and JS embedded.
5. Do not edit hooks, agents, rules, `.git/hooks`, `.claude`, `~/.codex`, project-external files, branches, remotes, or package files.
6. Do not run `git push`.

If the current tool environment cannot invoke the `html_builder` custom agent, do not silently substitute another agent. Report `BLOCKED` and ask whether local implementation without the custom agent is allowed.

## Page Requirements

Implement only `index.html`.

- Use semantic HTML.
- Put CSS in `<style>`.
- Put JS in `<script>` only when useful.
- Do not use external CDN, npm, React, Vue, or remote assets.
- Make the page open directly in a browser.
- Support mobile, tablet, and desktop layouts.
- Use realistic, user-topic-specific content.
- Avoid meaningless placeholder boxes.

Choose sections appropriate to the topic. For broad landing or information pages, prefer:

- Navigation
- Hero
- Core information section
- A suitable structured section, such as cards, table, timeline, comparison, map-like layout, or status grid
- Recommendation, summary, comparison, schedule, or current-status section
- CTA or usage guidance
- Footer

## Facts And Data

Do not invent unstable facts. Treat latest information, travel details, international affairs, prices, policies, availability, and schedules as changeable.

- Prefer user-provided data.
- If evidence is missing, label content as sample data or unverified.
- If the user requires current facts, gather authoritative sources before writing factual claims.

## Hooks And Verification

Do not invoke hook scripts directly.

- PostToolUse validation should run automatically after `index.html` is created or modified.
- Stop hook should run automatically at task end and perform its configured tests and auto-commit if trusted and possible.
- Inspect `.codex/hooks/hook.log` after editing to see whether PostToolUse logged.
- For Stop hook, report the observed auto-commit result if it has already happened. Otherwise report that it requires Codex `/hooks` trust and end-of-turn execution.

Validation responsibility belongs to configured hooks, not `test-runner`.

## Final Report

Keep the final report short and non-technical when the user is a non-developer. Include:

- Created or modified file path.
- Main sections included.
- Browser run method, usually opening `index.html` directly.
- Whether PostToolUse hook log was observed.
- Stop hook auto-commit result, or why it still needs confirmation.
- Explicitly state that `git push` was not run.
