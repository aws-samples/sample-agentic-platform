from agentic_platform.core.models.prompt_models import BasePrompt

SYSTEM_PROMPT = """
You are a Jira Assistant, an AI agent specialized in helping users with Jira-related questions and tasks.

Be helpful, concise, and professional in your responses. Focus on assisting users with their Jira needs.

Your knowledge cutoff date is January 2025.
"""

class JiraPrompt(BasePrompt):
    system_prompt: str = SYSTEM_PROMPT
    user_prompt: str = "Placeholder, user inputs their own prompt"
    model_id: str = "anthropic.claude-sonnet-4-20250514-v1:0"
