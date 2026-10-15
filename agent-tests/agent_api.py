"""Minimal client for the Agentforce Agent API (multi-turn conversations).

Needs an External Client App / Connected App with the client-credentials flow
and the `api`, `refresh_token`, `chatbot_api` and `sfap_api` scopes:
    AGENT_API_MY_DOMAIN      e.g. acme-dev-ed.develop.my.salesforce.com
    AGENT_API_CLIENT_ID      consumer key
    AGENT_API_CLIENT_SECRET  consumer secret
    AGENT_API_AGENT_ID       the agent's 0Xx... Id (Setup > Agentforce Agents)
"""
from __future__ import annotations

import os
import uuid
from dataclasses import dataclass, field

import requests

API_BASE = "https://api.salesforce.com/einstein/ai-agent/v1"


@dataclass
class AgentReply:
    messages: list[dict]

    @property
    def text(self) -> str:
        return "\n".join(m.get("message", "") for m in self.messages if m.get("message"))

    @property
    def types(self) -> set[str]:
        return {m.get("type", "") for m in self.messages}

    @property
    def is_handoff(self) -> bool:
        return "Escalation" in self.types


@dataclass
class AgentSession:
    client: "AgentClient"
    session_id: str
    greeting: AgentReply
    sequence: int = 0
    transcript: list[tuple[str, str]] = field(default_factory=list)

    def say(self, text: str) -> AgentReply:
        self.sequence += 1
        r = self.client.http.post(
            f"{API_BASE}/sessions/{self.session_id}/messages",
            json={"message": {"sequenceId": self.sequence, "type": "Text", "text": text}, "variables": []},
            timeout=120,
        )
        r.raise_for_status()
        reply = AgentReply(r.json().get("messages", []))
        self.transcript += [("customer", text), ("agent", reply.text)]
        return reply

    def end(self) -> None:
        self.client.http.delete(
            f"{API_BASE}/sessions/{self.session_id}", headers={"x-session-end-reason": "UserRequest"}, timeout=30
        )


class AgentClient:
    def __init__(self, my_domain: str, client_id: str, client_secret: str, agent_id: str):
        self.my_domain = my_domain.removeprefix("https://").rstrip("/")
        self.agent_id = agent_id
        token = requests.post(
            f"https://{self.my_domain}/services/oauth2/token",
            data={"grant_type": "client_credentials", "client_id": client_id, "client_secret": client_secret},
            timeout=30,
        )
        token.raise_for_status()
        self.http = requests.Session()
        self.http.headers.update({"Authorization": f"Bearer {token.json()['access_token']}"})

    @classmethod
    def from_env(cls) -> "AgentClient | None":
        names = ["AGENT_API_MY_DOMAIN", "AGENT_API_CLIENT_ID", "AGENT_API_CLIENT_SECRET", "AGENT_API_AGENT_ID"]
        values = [os.environ.get(n) for n in names]
        return cls(*values) if all(values) else None

    def start(self) -> AgentSession:
        r = self.http.post(
            f"{API_BASE}/agents/{self.agent_id}/sessions",
            json={
                "externalSessionKey": str(uuid.uuid4()),
                "instanceConfig": {"endpoint": f"https://{self.my_domain}"},
                "streamingCapabilities": {"chunkTypes": ["Text"]},
                "bypassUser": True,
            },
            timeout=60,
        )
        r.raise_for_status()
        body = r.json()
        return AgentSession(self, body["sessionId"], AgentReply(body.get("messages", [])))
