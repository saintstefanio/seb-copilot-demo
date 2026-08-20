---
name: jira
description: Read, search, comment on, update, and transition Jira Cloud issues via the REST API when no Jira MCP server is available. Use for any request mentioning a Jira issue key (e.g. PROJ-123), a JQL query, or moving a ticket between statuses.
---

# Jira (no-MCP fallback)

Drive Jira Cloud through `jira_connector.py`, a stdlib-only CLI in this repo.
Prefer a Jira MCP server if one is connected; use this when none is.

## Setup check

Requires three env vars: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`.
If a command fails with `KeyError`, one is missing — tell the user to set it
(token from https://id.atlassian.com/manage-profile/security/api-tokens) rather
than guessing values.

## Commands

Run from the repo root. All output is JSON.

```sh
python3 jira_connector.py get PROJ-123
python3 jira_connector.py search 'project = PROJ AND status = "In Progress"'
python3 jira_connector.py comment PROJ-123 "Deploying now."
python3 jira_connector.py update PROJ-123 '{"summary": "New summary"}'
python3 jira_connector.py transitions PROJ-123
python3 jira_connector.py transition PROJ-123 31
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

## In Python instead of the CLI

For an agent tool-calling loop, `jira_tools.py` exposes `TOOLS` (JSON-schema
specs) and `dispatch(name, args)`:

```python
from jira_tools import TOOLS, dispatch
result = dispatch("jira_get_issue", {"key": "PROJ-123"})
```

## Using this skill in another repo

Copy `SKILL.md`, `jira_connector.py`, and `jira_tools.py` into one directory
under `.github/skills/jira/` (or `~/.copilot/skills/jira/`), and drop the
"from the repo root" qualifier — the scripts sit beside `SKILL.md`.
