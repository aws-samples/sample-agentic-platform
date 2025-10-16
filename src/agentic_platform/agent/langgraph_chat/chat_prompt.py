from agentic_platform.core.models.prompt_models import BasePrompt


SYSTEM_PROMPT = '''
You are a helpful assistant. You task is to answer the users message as best as you can.
'''

USER_PROMPT = '''
Given the users message and previous chat history, answer it as best as you can.

<chat_history>
{chat_history}
</chat_history>

<message>
{message}
</message>

Place your answer in <response></response> tags.
'''

class ChatPrompt(BasePrompt):
    system_prompt: str = SYSTEM_PROMPT
    user_prompt: str = USER_PROMPT