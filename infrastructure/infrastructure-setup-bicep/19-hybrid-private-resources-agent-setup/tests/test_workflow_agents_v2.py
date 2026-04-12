#!/usr/bin/env python3
"""
Marketing Pipeline Workflow Test Script

Tests the sequential workflow that chains 3 agents via APIM gateway:
  1. Marketing Analyst — analyzes product features, audience, USPs
  2. Marketing Copywriter — composes compelling copy
  3. Marketing Editor — polishes the final output

Usage:
  export PROJECT_ENDPOINT="https://<ai-services>.services.ai.azure.com/api/projects/<project>"
  python test_workflow_agents_v2.py
"""

import os
import sys
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

PROJECT_ENDPOINT = os.environ.get(
    "PROJECT_ENDPOINT",
    "https://aiservicescdpy.services.ai.azure.com/api/projects/projectcdpy"
)
MODEL = os.environ.get("MODEL", "apim-gateway/gpt-4o-mini")

PRODUCT_DESCRIPTION = (
    "Describe a new AI-powered smart water bottle that tracks hydration, "
    "reminds you to drink, and syncs with fitness apps."
)


def test_workflow():
    """Test the marketing pipeline workflow end-to-end."""
    print("=" * 60)
    print("TEST: Marketing Pipeline Workflow (Sequential)")
    print("=" * 60)
    print(f"  Endpoint: {PROJECT_ENDPOINT}")

    try:
        with DefaultAzureCredential() as cred:
            with AIProjectClient(credential=cred, endpoint=PROJECT_ENDPOINT) as client:
                with client.get_openai_client() as openai:
                    # Ensure the 3 sub-agents exist
                    agents_config = [
                        ("marketing-analyst", "You are a marketing analyst. Identify key features, target audience, and USPs."),
                        ("marketing-copywriter", "You are a copywriter. Compose compelling ~150 word marketing copy."),
                        ("marketing-editor", "You are an editor. Polish grammar, clarity, tone, and formatting."),
                    ]
                    for name, instructions in agents_config:
                        client.agents.create_version(
                            agent_name=name,
                            definition=PromptAgentDefinition(model=MODEL, instructions=instructions),
                        )

                    # Create the workflow
                    workflow_yaml = """kind: workflow
name: marketing-pipeline
trigger:
  kind: OnConversationStart
  id: trigger_wf
  actions:
    - kind: InvokeAzureAgent
      id: analyst
      agent:
        name: marketing-analyst
      description: Analyze product features, audience, and USPs
      conversationId: =System.ConversationId
      input:
        messages: =System.LastMessage
      output:
        messages: Local.LatestMessage
        autoSend: true
    - kind: InvokeAzureAgent
      id: copywriter
      agent:
        name: marketing-copywriter
      description: Write compelling marketing copy from analysis
      conversationId: =System.ConversationId
      input:
        messages: =Local.LatestMessage
      output:
        messages: Local.LatestMessage
        autoSend: true
    - kind: InvokeAzureAgent
      id: editor
      agent:
        name: marketing-editor
      description: Polish and finalize the marketing copy
      conversationId: =System.ConversationId
      input:
        messages: =Local.LatestMessage
      output:
        messages: Local.LatestMessage
        autoSend: true
id: ""
description: "Sequential marketing pipeline: Analyst -> Copywriter -> Editor"
"""
                    workflow = client.agents.create_version(
                        agent_name="marketing-pipeline",
                        definition={
                            "kind": "workflow",
                            "name": "marketing-pipeline",
                            "description": "Sequential marketing pipeline",
                            "workflow": workflow_yaml,
                        },
                    )
                    print(f"  Workflow: {workflow.name}:{workflow.version}")

                    # Run the workflow
                    conv = openai.conversations.create()
                    print(f"  Conversation: {conv.id}")
                    print(f"  Input: {PRODUCT_DESCRIPTION}\n")

                    resp = openai.responses.create(
                        conversation=conv.id,
                        input=PRODUCT_DESCRIPTION,
                        extra_body={"agent": {"name": "marketing-pipeline", "type": "agent_reference"}},
                    )

                    print(f"  Status: {resp.status}")
                    print(f"  Output items: {len(resp.output)}")

                    # Extract message outputs (skip workflow_action items)
                    step_names = ["Analyst", "Copywriter", "Editor"]
                    step_idx = 0
                    for item in resp.output:
                        if item.type == "message" and hasattr(item, "content") and item.content:
                            label = step_names[step_idx] if step_idx < len(step_names) else f"Step {step_idx+1}"
                            text = item.content[0].text if item.content[0].text else "(empty)"
                            print(f"\n  === {label} Output ===")
                            print(f"  {text[:500]}")
                            step_idx += 1

                    print(f"\n  ✓ TEST PASSED: Workflow completed with {step_idx} agent outputs")
                    return True

    except Exception as e:
        print(f"\n  ✗ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    success = test_workflow()
    print("\n" + "=" * 60)
    print(f"Result: {'✓ PASSED' if success else '✗ FAILED'}")
    print("=" * 60)
    sys.exit(0 if success else 1)
