"""
OpenWebUI Pipe Function for DMO Claw

Deploy this as a Pipe Function in OpenWebUI Admin → Functions.
It forwards chat messages to the DMO Claw n8n webhook and returns the AI response.

Configuration:
- N8N_WEBHOOK_URL: Full webhook URL, e.g. https://your-n8n.example.com/webhook/dmo-claw
- BEARER_TOKEN: Must match the WEBHOOK_BEARER_TOKEN in your .env
"""

from pydantic import BaseModel, Field
import requests
from typing import Optional, Union, Generator, Iterator


class Pipe:
    class Valves(BaseModel):
        N8N_WEBHOOK_URL: str = Field(
            default="https://your-n8n.example.com/webhook/dmo-claw",
            description="n8n webhook URL for DMO Claw"
        )
        BEARER_TOKEN: str = Field(
            default="",
            description="Bearer token for webhook authentication"
        )

    def __init__(self):
        self.valves = self.Valves()

    def pipe(self, body: dict, __user__: dict = None) -> Union[str, Generator, Iterator]:
        # Skip OpenWebUI auto-generated follow-up requests
        messages = body.get("messages", [])
        if messages:
            last_msg = messages[-1].get("content", "")
            if "### Task:" in last_msg and "follow_ups" in last_msg:
                return ""

        # Inject user context into body so n8n can identify the user
        if __user__:
            body["user"] = {
                "email": __user__.get("email", ""),
                "name": __user__.get("name", "Unknown"),
                "role": __user__.get("role", "user"),
            }

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.valves.BEARER_TOKEN}"
        }

        try:
            response = requests.post(
                self.valves.N8N_WEBHOOK_URL,
                json=body,
                headers=headers,
                timeout=120
            )
            response.raise_for_status()
            data = response.json()
            return data.get("output", "No response from agent.")
        except requests.exceptions.Timeout:
            return "Agent response timed out. Please try again."
        except requests.exceptions.RequestException as e:
            return f"Error connecting to agent: {str(e)}"
