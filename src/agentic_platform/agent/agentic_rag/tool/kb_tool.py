"""Knowledge Base search tool for Strands."""

import os
import boto3
import logging
from strands import tool

logger = logging.getLogger(__name__)

# Initialize the client once at module level
knowledge_base_id = os.getenv('KNOWLEDGE_BASE_ID')

if not knowledge_base_id:
    raise ValueError("KNOWLEDGE_BASE_ID environment variable must be set")

client = boto3.client('bedrock-agent-runtime')

@tool
def search_knowledge_base(query: str) -> str:
    """Search the Bedrock knowledge base for relevant information.
    
    Args:
        query: The search query to find relevant information
        
    Returns:
        Relevant information from the knowledge base
    """
    try:
        response = client.retrieve(
            knowledgeBaseId=knowledge_base_id,
            retrievalQuery={'text': query},
            retrievalConfiguration={
                'vectorSearchConfiguration': {
                    'numberOfResults': 5
                }
            }
        )
        
        results = []
        for result in response.get('retrievalResults', []):
            content = result.get('content', {}).get('text', '')
            if content:
                results.append(content)
        
        if results:
            return "\n\n".join(results)
        else:
            return "No relevant information found in the knowledge base."
            
    except Exception as e:
        logger.error(f"Error querying knowledge base: {e}")
        return f"Error accessing knowledge base: {str(e)}"
