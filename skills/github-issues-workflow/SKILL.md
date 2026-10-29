---
name: github-issues-workflow
description: How to pick up, track, and report on a task that is a GitHub issue in this project's repository - reading it, the "In Progress" label, posting "<agent>:" comments, bug Resolution sections, commits. Use whenever the user refers to an issue by number, e.g. "work on github issue 11", "continue #11", "pick up 11", or just "work on 11".
---

# Working on a GitHub issue

A bare number ("work on 11", "#11") means issue 11 in this project's GitHub repository (the `origin` remote: `git remote get-url origin`). If there is no GitHub remote, ask the user which repository they mean.

## Starting

1. `git pull` locally. Stop if local is behind with uncommitted work or the histories diverged. Mention branches on GitHub or a cluster that aren't present locally.
2. Read the issue **and its latest comment**. If there is no clear next instruction, flag it and ask.
3. If the issue already has the "In Progress" label, warn the user (another session may own it) and wait for confirmation. Otherwise apply "In Progress".
4. Load whichever installed skill matches the work.

## While working

- Ask clarifying questions instead of guessing, and record the questions and answers on the issue.
- Slurm job names start with `gi<issue>_` (e.g. `gi11_train`).
- Work on the default branch (`main` or `master`); commit and push unless told otherwise. Prefix commit messages as CLAUDE.md specifies. Confirm before committing a **new** script; edits to existing ones need no confirmation.

## Reporting

- Post every update/summary as a **new comment** (`add_issue_comment` with the GitHub MCP server, or `gh issue comment`), starting with the same prefix as commit messages (e.g. `<agent>: `).
- Never edit the issue body for updates (`issue_write` with a `body`, or `gh issue edit --body`) - it overwrites the description. (Only exception: the bug Resolution below.)
- Don't repeat the posted comment in chat; give the main points only.
- When a step is done, remove "In Progress". Never close issues.

## Bugs

- For an issue labelled `bug`, once fixed or a workaround is settled: read the current body, then write it back **unchanged** with a `## Resolution` section appended (commits, files, what to do if you hit it).
- For any new pitfall you document, file a new `bug` issue (Symptom / Cause / Resolution) and add a row for it to the matching skill's debugging table, linking the issue by its full URL. A table can mix rows that link to the skill's `known-issues.md` (shared fixes) with rows that link to the user's own issues.
- If the pitfall looks generally applicable (it comes from the cluster, Slurm, a library or the agent rather than from this project's code), suggest that the user also file it at https://github.com/Alex-Shen-CMU/stats-agent-setup/issues so it can be added to the shared `known-issues.md`. Offer to draft it without project-specific details (project names, paths, usernames, allocations), and don't file it without the user's approval.
