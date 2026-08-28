# jira-connector

A dependency-free Jira Cloud CLI for agents — a fallback for reading, updating,
and commenting on Jira Cloud issues when an MCP server isn't available. It ships
two interchangeable front ends and needs no Python, Node, package manager, or
separately installed runtime:

- `jira` — Bash + `curl`, for macOS, Linux, Git Bash, and WSL.
- `jira.ps1` — pure PowerShell, for Windows where `bash` isn't installed.

Both wrap the Jira REST API, take identical subcommands, and print identical
JSON. The Jira REST API itself can be called from any language.

## Setup

No install step. On macOS/Linux, make the Bash script executable:

```sh
chmod +x jira
```

On Windows nothing is needed; run `.\jira.ps1` directly.

### Auth modes

The connector supports both Jira flavours and picks the mode automatically from
the variables you provide:

| Mode | Set these | Auth sent | REST API |
| --- | --- | --- | --- |
| Jira **Cloud** (`*.atlassian.net`) | `JIRA_EMAIL` + `JIRA_API_TOKEN` | Basic | v3 |
| Jira **Server / Data Center** (self-hosted) | `JIRA_PERSONAL_ACCESS_TOKEN` | Bearer | v2 |

`JIRA_BASE_URL` is required in both. If `JIRA_PERSONAL_ACCESS_TOKEN` is set it
takes precedence and Server/DC mode is used; otherwise the connector falls back
to Cloud mode and requires the email/token pair.

Provide the settings either as environment variables:

```sh
export JIRA_BASE_URL="https://acme.atlassian.net"
export JIRA_EMAIL="you@example.com"
export JIRA_API_TOKEN="paste-here"
```

```sh
# ...or, for a self-hosted Jira Server / Data Center instance:
export JIRA_BASE_URL="https://jira.acme.example"
export JIRA_PERSONAL_ACCESS_TOKEN="paste-here"
```

…or in a `.env` file, which both scripts auto-load from the script's directory,
its parent, or the current directory:

```ini
JIRA_BASE_URL=https://acme.atlassian.net
JIRA_EMAIL=you@example.com
JIRA_API_TOKEN=paste-here
# Server/Data Center instead:
# JIRA_PERSONAL_ACCESS_TOKEN=paste-here
```

Real environment variables take precedence over `.env`. The file is read as
plain `KEY=VALUE` pairs, never executed. Keep `.env` out of version control.

> Because `.env` values are only applied when the variable is not already set,
> leaving `JIRA_PERSONAL_ACCESS_TOKEN` in `.env` pins the connector to
> Server/DC mode. Comment it out to go back to Cloud mode.

`JIRA_BASE_URL` is just your Jira site's origin: no `/jira` or `/rest` suffix; a
trailing slash is trimmed for you. Create a classic Cloud API token at
[Atlassian account security](https://id.atlassian.com/manage-profile/security/api-tokens),
or a Server/DC personal access token under *Profile → Personal Access Tokens* on
your Jira host. Treat either as a password; never commit it.

A Cloud token (`ATATT…`) will not authenticate against a Server/DC host and vice
versa — a 401 on every command usually means the token type does not match the
host in `JIRA_BASE_URL`.

## Verify

The offline check needs no network or credentials:

```sh
./jira selfcheck          # macOS / Linux
.\jira.ps1 selfcheck      # Windows
```

Then verify the credentials — Jira Cloud:

```sh
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/myself" | head -c 200
```

…or Jira Server / Data Center:

```sh
curl -s -H "Authorization: Bearer $JIRA_PERSONAL_ACCESS_TOKEN" \
  "$JIRA_BASE_URL/rest/api/2/myself" | head -c 200
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

On Windows, substitute `.\jira.ps1` for `./jira`:

```powershell
.\jira.ps1 get PROJ-123
.\jira.ps1 comment PROJ-123 "Deploying now."
```

## Agent skill

`.github/skills/jira/SKILL.md` gives Copilot and Claude Code the command syntax.
To use it elsewhere, copy `SKILL.md`, `jira`, and `jira.ps1` into one directory
under the agent's skill folder, then run `chmod +x jira`.

> Targets Jira Cloud REST API v3 with Basic authentication, and Jira Server /
> Data Center REST API v2 with personal-access-token authentication. The mode
> is selected automatically from the variables you set.
