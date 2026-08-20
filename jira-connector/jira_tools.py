"""Framework-neutral tool wrapper around JiraConnector.

Exposes the connector as a flat list of tool specs (name + description +
JSON-schema params) plus a single dispatch(name, args) entrypoint. Any agent
loop that does function/tool calling can feed it TOOLS and route calls through
dispatch — no framework-specific packaging.

    from jira_tools import TOOLS, dispatch
    # give TOOLS to your model as tool definitions, then on a tool call:
    result = dispatch(call.name, call.arguments)
"""
from __future__ import annotations

from jira_connector import JiraConnector

_STRING = {"type": "string"}


def _spec(name, description, required, properties):
    return {
        "name": name,
        "description": description,
        "parameters": {
            "type": "object",
            "properties": properties,
            "required": required,
        },
    }


TOOLS = [
    _spec("jira_get_issue", "Fetch a Jira issue by key.", ["key"],
          {"key": _STRING,
           "fields": {"type": "string",
                      "description": "Comma-separated field list.",
                      "default": "summary,status,assignee,description"}}),
    _spec("jira_search", "Search issues with a JQL query.", ["jql"],
          {"jql": _STRING,
           "max_results": {"type": "integer", "default": 20}}),
    _spec("jira_add_comment", "Add a comment to an issue.", ["key", "text"],
          {"key": _STRING, "text": _STRING}),
    _spec("jira_update_fields", "Update fields on an issue.", ["key", "fields"],
          {"key": _STRING,
           "fields": {"type": "object",
                      "description": 'Field map, e.g. {"summary": "..."}.'}}),
    _spec("jira_list_transitions", "List available status transitions.", ["key"],
          {"key": _STRING}),
    _spec("jira_transition", "Move an issue to a new status by transition id.",
          ["key", "transition_id"],
          {"key": _STRING, "transition_id": _STRING}),
]


def _handlers(j):
    return {
        "jira_get_issue": lambda a: j.get_issue(a["key"], a.get("fields", "summary,status,assignee,description")),
        "jira_search": lambda a: j.search(a["jql"], max_results=a.get("max_results", 20)),
        "jira_add_comment": lambda a: j.add_comment(a["key"], a["text"]),
        "jira_update_fields": lambda a: (j.update_fields(a["key"], a["fields"]), {"ok": True})[1],
        "jira_list_transitions": lambda a: j.list_transitions(a["key"]),
        "jira_transition": lambda a: (j.transition(a["key"], a["transition_id"]), {"ok": True})[1],
    }


def dispatch(name, args):
    """Run a tool call by name. Returns a JSON-serializable result."""
    handlers = _handlers(JiraConnector())
    if name not in handlers:
        raise KeyError(f"unknown tool: {name}")
    return handlers[name](args)


def _selfcheck():
    # Advertised tools and handlers agree, no auth/network needed.
    handler_names = set(_handlers(object()))  # object() ok: never called
    tool_names = {t["name"] for t in TOOLS}
    assert tool_names == handler_names, tool_names ^ handler_names
    print("selfcheck ok")


if __name__ == "__main__":
    _selfcheck()
