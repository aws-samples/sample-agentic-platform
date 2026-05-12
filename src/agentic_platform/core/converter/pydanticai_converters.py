from typing import Dict, List, Any

from pydantic_ai.messages import ModelMessage
from pydantic_core import to_jsonable_python

from agentic_platform.core.models.memory_models import Message, ToolCall, ToolResult

from typing import Dict, List, Any

from pydantic_ai.messages import ModelMessage
from pydantic_core import to_jsonable_python

from agentic_platform.core.models.memory_models import Message, ToolCall, ToolResult
from typing import Dict, Any, List, Union, Optional
from datetime import datetime
from uuid import uuid4

from agentic_platform.core.models.streaming_models import (
    StreamEvent, TextDeltaEvent, 
    ToolCallEvent, ToolResultEvent, ErrorEvent, DoneEvent,
    StreamEventType
)

class PydanticAIMessageConverter:

    @classmethod
    def convert_tool_call(cls, tool_call: Dict[str, Any]) -> ToolCall:
        return ToolCall(
            name=tool_call['tool_name'],
            arguments=tool_call['args'],
            id=tool_call['tool_call_id']
        )

    @classmethod
    def convert_tool_result(cls, tool_result: Dict[str, Any]) -> ToolResult:
        return ToolResult(
            id=tool_result['tool_call_id'],
            content=ToolResult.to_content(tool_result['content']),
            isError=False
        )

    @classmethod
    def convert_text(cls, text: Dict[str, Any]) -> str:
        return text['content']

    @classmethod
    def convert_message(cls, message: Dict[str, Any]) -> Message:
        # Create a dictionary to store the message parts.
        message_dict: Dict[str, Any] = {}

        # PydanticAI kind field is either request/response. It does not have a specific tool field like LangChain.
        role: str = 'user' if message['kind'] == 'request' else 'assistant'

        message_dict['role'] = role

        # For each part handle the type appropriately.
        for part in message['parts']:
            # Grab the part kind.
            part_kind: str = part['part_kind']

            # Handle the type appropriately.
            if part_kind == 'text' or part_kind == 'user-prompt':
                message_dict['text'] = cls.convert_text(part)

            elif part_kind == 'tool-call':
                tool_call: ToolCall = cls.convert_tool_call(part)
                message_dict.setdefault("tool_calls", []).append(tool_call)

            elif part_kind == 'tool-return':
                tool_result: ToolResult = cls.convert_tool_result(part)
                message_dict.setdefault("tool_results", []).append(tool_result)

        return Message(**message_dict)

    @classmethod
    def convert_messages(cls, messages: List[ModelMessage]) -> List[Message]:
        json_messages: List[Dict[str, Any]] = to_jsonable_python(messages)
        return [cls.convert_message(message) for message in json_messages]
    
class PydanticAIStreamingEventConverter:
    """Converter class for handling individual stream events from PydanticAI"""

    @classmethod
    def convert_event(cls, event: Dict[str, Any], session_id: str) -> List[StreamEvent]:
        """Convert a single streaming event to StreamEvent(s)"""
        events = []
        
        # Skip initial user prompt and system prompts - we don't want these in the stream
        if 'user_prompt' in event:
            return events  # Return empty list
        
        # Skip request parts that are system/user prompts
        elif 'request' in event and 'parts' in event['request']:
            for part in event['request']['parts']:
                part_kind = part.get('part_kind')
                
                # Only handle tool returns, skip prompts
                if part_kind == 'tool-return':
                    tool_result = ToolResult(
                        id=part['tool_call_id'],
                        content=ToolResult.to_content(part['content']),
                        isError=False
                    )
                    events.append(ToolResultEvent(
                        session_id=session_id,
                        tool_result=tool_result,
                        metadata={
                            'timestamp': part.get('timestamp'),
                            'part_kind': part_kind
                        }
                    ))
        
        # Handle model response with parts
        elif 'model_response' in event and 'parts' in event['model_response']:
            for part in event['model_response']['parts']:
                part_kind = part.get('part_kind')
                
                if part_kind == 'text':
                    events.append(TextDeltaEvent(
                        session_id=session_id,
                        text=part['content'],
                        metadata={
                            'timestamp': part.get('timestamp'),
                            'part_kind': part_kind
                        }
                    ))
                
                elif part_kind == 'tool-call':
                    tool_call = ToolCall(
                        name=part['tool_name'],
                        arguments=part['args'],
                        id=part['tool_call_id']
                    )
                    events.append(ToolCallEvent(
                        session_id=session_id,
                        tool_call=tool_call,
                        metadata={
                            'timestamp': part.get('timestamp'),
                            'part_kind': part_kind
                        }
                    ))
        
        # Handle final data/output - emit a final TextDeltaEvent (with is_final metadata) followed by DoneEvent
        elif 'data' in event and event['data'].get('output'):
            events.append(TextDeltaEvent(
                session_id=session_id,
                text=event['data']['output'],
                metadata={'is_final': True}
            ))

            events.append(DoneEvent(
                session_id=session_id,
                metadata={
                    'timestamp': datetime.now().timestamp(),
                    'is_final': True
                }
            ))
        
        return events

    @classmethod
    def convert_part(cls, part: Dict[str, Any], session_id: str, context: str = None) -> Optional[StreamEvent]:
        """Convert a single part to a StreamEvent"""
        part_kind = part.get('part_kind')
        
        if part_kind == 'text':
            return TextDeltaEvent(
                session_id=session_id,
                text=part['content'],
                metadata={
                    'timestamp': part.get('timestamp'),
                    'part_kind': part_kind,
                    'context': context
                }
            )
        
        elif part_kind == 'tool-call':
            tool_call = ToolCall(
                name=part['tool_name'],
                arguments=part['args'],
                id=part['tool_call_id']
            )
            return ToolCallEvent(
                session_id=session_id,
                tool_call=tool_call,
                metadata={
                    'timestamp': part.get('timestamp'),
                    'part_kind': part_kind,
                    'context': context
                }
            )
        
        elif part_kind == 'tool-return':
            tool_result = ToolResult(
                id=part['tool_call_id'],
                content=ToolResult.to_content(part['content']),
                isError=False
            )
            return ToolResultEvent(
                session_id=session_id,
                tool_result=tool_result,
                metadata={
                    'timestamp': part.get('timestamp'),
                    'part_kind': part_kind,
                    'context': context
                }
            )
        
        return None

    @classmethod
    def convert_single_event(cls, event: Dict[str, Any], session_id: str) -> Optional[StreamEvent]:
        """Convert a single streaming event to one StreamEvent (returns first if multiple)"""
        events = cls.convert_event(event, session_id)
        return events[0] if events else None

    @classmethod
    def detect_event_type(cls, event: Dict[str, Any]) -> str:
        """Helper method to detect what type of event this is"""
        if 'user_prompt' in event:
            return 'initial_prompt'  # Will be skipped
        elif 'request' in event:
            return 'request'
        elif 'model_response' in event:
            return 'model_response'
        elif 'data' in event and event['data'].get('output'):
            return 'final_output'
        else:
            return 'unknown'