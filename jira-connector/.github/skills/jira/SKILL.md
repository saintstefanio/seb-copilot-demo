---
name: jira
description: Read, search, comment on, update, and transition Jira Cloud issues via the REST API when no Jira MCP server is available. Use for any request mentioning a Jira issue key (e.g. PROJ-123), a JQL query, or moving a ticket between statuses.
---

# Jira (no-MCP fallback)

Drive Jira Cloud through `./jira`, a Bash-and-curl CLI in this repo. It needs no
Python, Node, package install, or separately installed runtime.
Prefer a Jira MCP server if one is connected; use this when none is.

## Setup check

Requires three env vars: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`.
If a command reports a missing variable, tell the user to set it
(token from https://id.atlassian.com/manage-profile/security/api-tokens) rather
than guessing values.

## Commands

Run from the repo root. All output is JSON.

```sh
./jira get PROJ-123
./jira search 'project = PROJ AND status = "In Progress"'
./jira comment PROJ-123 "Deploying now."
./jira update PROJ-123 '{"summary": "New summary"}'
./jira transitions PROJ-123
./jira transition PROJ-123 31
```

## Rules

- **Status changes are transitions, not field writes.** Never
  `update ... '{"status": ...}'`. Run `transitions <key>` first to get the valid
  transition ids for that issue's current status, then `transition <key> <id>`.
  Transition ids differ per project and per current status — never reuse an id
  from a previous issue or from these examples.
- **Confirm before writing.** `comment`, `update`, and `transition` are visible
  to everyone on the ticket and are not cleanly undoable. Show the user the exact
  command first unless they already asked for that specific change.
- Comments are plain text; the connector wraps them in Atlassian Document Format.
- `search` returns 20 results by default. Narrow the JQL rather than paging.
- Quote JQL in single quotes — it contains double quotes and `=`.

## Using this skill in another repo

Copy `SKILL.md` and `jira` into one directory
under `.github/skills/jira/` (or `~/.copilot/skills/jira/`), and drop the
"from the repo root" qualifier — the scripts sit beside `SKILL.md`.
