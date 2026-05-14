# Centralized Bedrock model IDs — single place to bump when models are deprecated.
# Agents can import and override these per-agent if needed.
#
# Two forms exist because LiteLLM proxy routing uses the non-prefixed model name
# (e.g. "anthropic.claude-...") while direct Bedrock API calls need the region-
# prefixed form (e.g. "us.anthropic.claude-...").

# Direct Bedrock API calls (BedrockModel, bedrock-runtime converse)
HAIKU_MODEL_ID = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
SONNET_MODEL_ID = "us.anthropic.claude-sonnet-4-20250514-v1:0"
NOVA_LITE_MODEL_ID = "us.amazon.nova-lite-v1:0"

# LiteLLM proxy model names (must match model_name entries in litellm_config.yaml)
HAIKU_LITELLM_MODEL_ID = "anthropic.claude-haiku-4-5-20251001-v1:0"
SONNET_LITELLM_MODEL_ID = "anthropic.claude-sonnet-4-20250514-v1:0"
