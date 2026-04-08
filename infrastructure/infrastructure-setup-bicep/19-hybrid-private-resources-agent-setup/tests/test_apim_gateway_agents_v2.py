#!/usr/bin/env python3
"""
APIM Gateway Agent Test Script

Tests that a Foundry prompt agent can route model requests through an APIM
gateway connection, following the AI Gateway docs:
https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway

Key pattern: The model deployment name uses the format <connection-name>/<model-name>
so Agent Service knows to route through the APIM gateway.

Prerequisites:
  pip install azure-ai-projects azure-identity openai

Usage:
  export PROJECT_ENDPOINT="https://<ai-services>.services.ai.azure.com/api/projects/<project>"
  export APIM_CONNECTION_NAME="apim-gateway"
  export APIM_MODEL_NAME="gpt-4o-mini"
  python test_apim_gateway_agents_v2.py
"""

import os
import sys
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logging.getLogger("azure.core.pipeline.policies.http_logging_policy").setLevel(logging.INFO)
logging.getLogger("httpx").setLevel(logging.INFO)
logging.getLogger("urllib3").setLevel(logging.WARNING)
logging.getLogger("azure.identity").setLevel(logging.WARNING)

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ENDPOINT = os.environ.get(
    "PROJECT_ENDPOINT",
    "https://aiservicescdpy.services.ai.azure.com/api/projects/projectcdpy"
)
APIM_CONNECTION_NAME = os.environ.get("APIM_CONNECTION_NAME", "apim-gateway")
APIM_MODEL_NAME = os.environ.get("APIM_MODEL_NAME", "gpt-4o-mini")

# The gateway model deployment name format: <connection-name>/<model-name>
GATEWAY_MODEL = f"{APIM_CONNECTION_NAME}/{APIM_MODEL_NAME}"
# ============================================================================


def test_apim_gateway_agent():
    """Test prompt agent routing requests through APIM gateway."""
    print("\n" + "=" * 60)
    print("TEST: APIM Gateway Agent (Prompt Agent via AI Gateway)")
    print("=" * 60)
    print(f"  Project Endpoint: {PROJECT_ENDPOINT}")
    print(f"  Gateway Model:    {GATEWAY_MODEL}")

    agent = None

    try:
        with (
            DefaultAzureCredential() as credential,
            AIProjectClient(
                credential=credential,
                endpoint=PROJECT_ENDPOINT
            ) as project_client,
            project_client.get_openai_client() as openai_client,
        ):
            print(f"✓ Connected to AI Project")

            # Create a prompt agent that routes through the APIM gateway
            agent = project_client.agents.create_version(
                agent_name="apim-gateway-test-agent",
                definition=PromptAgentDefinition(
                    model=GATEWAY_MODEL,
                    instructions="You are a helpful assistant. Answer briefly and concisely.",
                ),
            )
            print(f"✓ Created agent (id: {agent.id}, model: {GATEWAY_MODEL})")

            # Create a conversation
            conversation = openai_client.conversations.create()
            print(f"✓ Created conversation: {conversation.id}")

            # Send a request — this should route through APIM to the model
            response = openai_client.responses.create(
                conversation=conversation.id,
                input="Say hello and confirm you are working through an API gateway. Keep it brief.",
                extra_body={"agent": {"name": agent.name, "type": "agent_reference"}},
            )

            print(f"\n✓ Agent response: {response.output_text}")
            print("\n✓ TEST PASSED: Prompt agent successfully routed through APIM gateway")
            print(f"\n  Agent kept alive: name={agent.name}, version={agent.version}")
            print(f"  Use model name '{GATEWAY_MODEL}' to invoke it.")

            return True

    except Exception as e:
        print(f"\n✗ TEST FAILED: {str(e)}")
        import traceback
        traceback.print_exc()

        if "model not found" in str(e).lower():
            print("\n  💡 Tip: Verify FOUNDRY_MODEL_DEPLOYMENT_NAME uses format:")
            print(f"     {APIM_CONNECTION_NAME}/<model-name>")
            print("     Check that the model is listed in the APIM connection's static models.")

        return False


if __name__ == "__main__":
    print("APIM Gateway Agent Test")
    print(f"Using gateway model: {GATEWAY_MODEL}")

    success = test_apim_gateway_agent()

    print("\n" + "=" * 60)
    print(f"Result: {'✓ PASSED' if success else '✗ FAILED'}")
    print("=" * 60)

    sys.exit(0 if success else 1)
