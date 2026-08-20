"""Standalone Jira connector — zero-dependency fallback for agents when MCP is unavailable.

Read, update, comment on, and transition Jira Cloud issues via REST API v3.
Usable as an importable class or a CLI. Stdlib only (urllib), so it drops into
any agent runtime without installing anything.

Auth via env vars (or constructor args):
  JIRA_BASE_URL   https://your-domain.atlassian.net
  JIRA_EMAIL      your Atlassian account email
  JIRA_API_TOKEN  https://id.atlassian.com/manage-profile/security/api-tokens

ponytail: Jira *Cloud* (API v3, Basic auth). For Server/Data Center switch the
path to /rest/api/2 and the auth header to "Bearer <PAT>".
"""
from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request


class JiraError(RuntimeError):
    """HTTP or API error from Jira."""


class JiraConnector:
    def __init__(self, base_url=None, email=None, api_token=None):
        self.base_url = (base_url or os.environ["JIRA_BASE_URL"]).rstrip("/")
        email = email or os.environ["JIRA_EMAIL"]
        token = api_token or os.environ["JIRA_API_TOKEN"]
        self._auth = "Basic " + base64.b64encode(f"{email}:{token}".encode()).decode()

    def _request(self, method, path, body=None):
        url = f"{self.base_url}/rest/api/3{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", self._auth)
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise JiraError(f"{method} {path} -> {e.code}: {detail}") from None

    # --- read ---
    def get_issue(self, key, fields="summary,status,assignee,description"):
        return self._request("GET", f"/issue/{key}?fields={fields}")

    def search(self, jql, fields=("summary", "status"), max_results=20):
        # ponytail: /search/jql is the current endpoint; old /search was deprecated 2025.
        body = {"jql": jql, "maxResults": max_results, "fields": list(fields)}
        return self._request("POST", "/search/jql", body)

    def list_transitions(self, key):
        return self._request("GET", f"/issue/{key}/transitions")

    # --- write ---
    def update_fields(self, key, fields):
        self._request("PUT", f"/issue/{key}", {"fields": fields})

    def add_comment(self, key, text):
        return self._request("POST", f"/issue/{key}/comment", {"body": _adf(text)})

    def transition(self, key, transition_id):
        self._request("POST", f"/issue/{key}/transitions",
                      {"transition": {"id": str(transition_id)}})


def _adf(text):
    """Wrap plain text as an Atlassian Document Format doc (required by API v3)."""
    return {
        "type": "doc",
        "version": 1,
        "content": [{"type": "paragraph",
                     "content": [{"type": "text", "text": text}]}],
    }


def _selfcheck():
    # Offline checks for the two non-trivial bits: ADF shape and auth encoding.
    doc = _adf("hello")
    assert doc["content"][0]["content"][0]["text"] == "hello"
    assert doc["type"] == "doc" and doc["version"] == 1
    c = JiraConnector(base_url="https://x.atlassian.net/", email="a@b.co", api_token="tok")
    assert c.base_url == "https://x.atlassian.net"  # trailing slash stripped
    scheme, b64 = c._auth.split(" ")
    assert scheme == "Basic"
    assert base64.b64decode(b64).decode() == "a@b.co:tok"
    print("selfcheck ok")


def main():
    import sys

    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("usage: jira_connector.py <get|search|comment|update|transitions|transition|selfcheck> ...")
        sys.exit(0)
    cmd, rest = args[0], args[1:]
    if cmd == "selfcheck":
        _selfcheck()
        sys.exit(0)

    j = JiraConnector()
    if cmd == "get":
        print(json.dumps(j.get_issue(rest[0]), indent=2))
    elif cmd == "search":
        print(json.dumps(j.search(rest[0]), indent=2))
    elif cmd == "comment":
        print(json.dumps(j.add_comment(rest[0], rest[1]), indent=2))
    elif cmd == "update":
        j.update_fields(rest[0], json.loads(rest[1]))  # e.g. '{"summary":"new"}'
        print("updated")
    elif cmd == "transitions":
        print(json.dumps(j.list_transitions(rest[0]), indent=2))
    elif cmd == "transition":
        j.transition(rest[0], rest[1])
        print("transitioned")
    else:
        print(f"unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
