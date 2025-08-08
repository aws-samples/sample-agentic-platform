"""Converter for Strands streaming events to platform streaming types."""

import logging
import json
from typing import List, Dict, Optional, Any

from agentic_platform.core.models.streaming_models import (
    StreamEvent, StartEvent, TextDeltaEvent, ContentBlockStart, 
    ContentBlockEnd, ErrorEvent, DoneEvent,
    ToolCallEvent, ToolCallDeltaEvent, ToolResultEvent
)
from agentic_platform.core.models.memory_models import ToolCall, ToolResult, TextContent

logger = logging.getLogger(__name__)


class StrandsStreamingConverter:
    """Converts Strands streaming chunks to platform streaming events."""
    
    def __init__(self, session_id: str):
        """Initialize the converter."""
        self.session_id = session_id

    def convert_message_start(self, event: Dict[str, Any]) -> List[StreamEvent]:
        """Convert messageStart event."""
        return [StartEvent(session_id=self.session_id)]

    def convert_content_block_start(self, event: Dict[str, Any]) -> List[StreamEvent]:
        """Convert contentBlockStart event."""
        start_data = event.get('start', {})
        is_tool_call = 'toolUse' in start_data
        
        if is_tool_call:
            # Tool call starting - convert toolUse to ToolCall object
            tool_use = start_data['toolUse']
            tool_call = ToolCall(
                name=tool_use.get('name', ''),
                arguments={},  # Arguments will be built up through deltas
                id=tool_use.get('toolUseId', '')
            )
            return [ContentBlockStart(
                session_id=self.session_id,
                content_type="tool_call",
                content_block={"toolCall": tool_call.model_dump()}
            )]
        else:
            # Text block starting
            return [ContentBlockStart(
                session_id=self.session_id,
                content_type="text",
                content_block={"text": ""}
            )]

    def convert_content_block_delta(self, event: Dict[str, Any]) -> List[StreamEvent]:
        """Convert contentBlockDelta event."""
        delta = event.get('delta', {})
        
        if 'text' in delta:
            # Text delta
            return [TextDeltaEvent(
                session_id=self.session_id,
                text=delta['text']
            )]
        elif 'toolUse' in delta:
            # Tool use delta
            input_delta = delta['toolUse'].get('input', '')
            return [ToolCallDeltaEvent(
                session_id=self.session_id,
                arguments_delta=input_delta
            )]
        
        return []

    def convert_content_block_stop(self, event: Dict[str, Any]) -> List[StreamEvent]:
        """Convert contentBlockStop event."""
        return [ContentBlockEnd(
            session_id=self.session_id,
            text=""
        )]

    def convert_message_stop(self, event: Dict[str, Any]) -> List[StreamEvent]:
        """Convert messageStop event."""
        stop_reason = event.get('stopReason', 'end_turn')
        return [DoneEvent(
            session_id=self.session_id,
            metadata={"stop_reason": stop_reason}
        )]

    def convert_event(self, event: Dict[str, Any]) -> List[StreamEvent]:
        """Convert a single event."""
        if 'messageStart' in event:
            return self.convert_message_start(event['messageStart'])
        elif 'contentBlockStart' in event:
            return self.convert_content_block_start(event['contentBlockStart'])
        elif 'contentBlockDelta' in event:
            return self.convert_content_block_delta(event['contentBlockDelta'])
        elif 'contentBlockStop' in event:
            return self.convert_content_block_stop(event['contentBlockStop'])
        elif 'messageStop' in event:
            return self.convert_message_stop(event['messageStop'])
        elif 'metadata' in event:
            # Skip metadata events
            return []
        
        return []

    def convert_message(self, message: Dict[str, Any]) -> List[StreamEvent]:
        """Convert a complete message to events."""
        events = []
        
        if message.get('role') == 'user':
            # Check for tool results - make them standalone events (no content blocks)
            content = message.get('content', [])
            for content_item in content:
                if 'toolResult' in content_item:
                    tool_result_data = content_item['toolResult']
                    
                    # Tool result event (standalone, no content block)
                    tool_result = ToolResult(
                        id=tool_result_data.get('toolUseId', ''),
                        content=[TextContent(text=item.get('text', '')) for item in tool_result_data.get('content', [])],
                        isError=tool_result_data.get('status') != 'success'
                    )
                    events.append(ToolResultEvent(
                        session_id=self.session_id,
                        tool_result=tool_result
                    ))
                    
        elif message.get('role') == 'assistant':
            # Check for tool calls - make them standalone events (no content blocks)
            content = message.get('content', [])
            for content_item in content:
                if 'toolUse' in content_item:
                    tool_use = content_item['toolUse']
                    
                    # Tool call event (standalone, no content block)
                    tool_call = ToolCall(
                        name=tool_use.get('name', ''),
                        arguments=tool_use.get('input', {}),
                        id=tool_use.get('toolUseId', '')
                    )
                    events.append(ToolCallEvent(
                        session_id=self.session_id,
                        tool_call=tool_call
                    ))
        
        return events

    def convert_chunks_to_events(self, chunk: Dict[str, Any]) -> List[StreamEvent]:
        """Convert Strands streaming chunk to platform streaming events."""
        try:
            if 'event' in chunk:
                return self.convert_event(chunk['event'])
            elif 'message' in chunk:
                return self.convert_message(chunk['message'])
            else:
                return []
        except Exception as e:
            logger.error(f"Error converting chunk: {e}")
            return [ErrorEvent(
                session_id=self.session_id,
                error=f"Error processing event: {str(e)}"
            )]
