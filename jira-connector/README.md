# jira-connector

A dependency-free Jira Cloud CLI for agents — a fallback for reading, updating,
and commenting on Jira Cloud issues when an MCP server isn't available. It uses
only Bash and `curl`: no Python, Node, package manager, or separately installed
runtime.

`jira` is a portable shell wrapper around Jira's REST API. `curl` is bundled with
current macOS, Linux distributions, and Windows; on Windows run it from Git Bash
or WSL. The Jira REST API itself can be called from any language.

## Setup

No install step — copy `jira` beside the agent skill and make it executable:

```sh
chmod +x jira
```

Set three environment variables:

```sh
export JIRA_BASE_URL="https://acme.atlassian.net"
export JIRA_EMAIL="you@example.com"
export JIRA_API_TOKEN="paste-here"
```

`JIRA_BASE_URL` is just your Jira site's origin: no `/jira` or `/rest` suffix.
Create a classic API token at
[Atlassian account security](https://id.atlassian.com/manage-profile/security/api-tokens).
Treat it as a password; never commit it.

## Verify

The offline check needs no network or credentials:

```sh
./jira selfcheck
```

Then verify the credentials:

```sh
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/myself" | head -c 200
```

## Commands

```sh
./jira get PROJ-123
./jira search 'project = PROJ AND status = "In Progress"'
./jira comment PROJ-123 "Deploying now."
./jira update PROJ-123 '{"summary": "New summary"}'
./jira transitions PROJ-123
./jira transition PROJ-123 31
```

`comment`, `update`, and `transition` write to Jira. Confirm the intended change
before running them. Status changes are transitions, not `update` field writes:
list the issue's transitions first and use the returned ID.

## Agent skill

`.github/skills/jira/SKILL.md` gives Copilot and Claude Code the command syntax.
To use it elsewhere, copy `SKILL.md` and `jira` into one directory under the
agent's skill folder, then run `chmod +x jira`.

> Targets Jira Cloud REST API v3 with Basic authentication. For Jira Server/Data
> Center, use `/rest/api/2` and a `Bearer <PAT>` header instead.
