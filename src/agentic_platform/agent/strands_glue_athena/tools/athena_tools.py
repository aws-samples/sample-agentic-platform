"""
Tools for interacting with Amazon Athena.
"""
import boto3
import time
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from strands import tool


class AthenaQueryResult(BaseModel):
    """Result of an Athena query."""
    query_id: str
    query: str
    status: str
    columns: List[str] = []
    data: List[Dict[str, Any]] = []
    row_count: int = 0
    execution_time_ms: Optional[int] = None
    error_message: Optional[str] = None


@tool
def run_athena_query(
    query: str,
    database: str,
    output_location: Optional[str] = None,
    wait_for_results: bool = True,
    max_wait_seconds: int = 60
) -> AthenaQueryResult:
    """
    Run a SQL query on Amazon Athena.
    
    Args:
        query: The SQL query to execute
        database: The Athena database to query
        output_location: S3 location for query results (optional, uses default if not specified)
        wait_for_results: Whether to wait for query completion (default: True)
        max_wait_seconds: Maximum time to wait for results in seconds (default: 60)
    
    Returns:
        An AthenaQueryResult containing query results or status
    """
    # Initialize Athena client
    athena_client = boto3.client('athena')
    
    start_time = time.time()
    
    try:
        # Start query execution
        start_query_response = athena_client.start_query_execution(
            QueryString=query,
            QueryExecutionContext={
                'Database': database
            },
            ResultConfiguration={
                'OutputLocation': output_location
            } if output_location else {}
        )
        
        query_execution_id = start_query_response['QueryExecutionId']
        
        # Initialize result
        result = AthenaQueryResult(
            query_id=query_execution_id,
            query=query,
            status="SUBMITTED"
        )
        
        # If not waiting for results, return immediately
        if not wait_for_results:
            return result
        
        # Wait for query to complete
        state = 'RUNNING'
        while state in ['QUEUED', 'RUNNING'] and (time.time() - start_time) < max_wait_seconds:
            response = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
            state = response['QueryExecution']['Status']['State']
            
            if state in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
                break
                
            time.sleep(1)  # Wait before checking again
        
        # Update status
        result.status = state
        
        # If query completed successfully, get results
        if state == 'SUCCEEDED':
            # Calculate execution time
            if 'QueryExecution' in response and 'Statistics' in response['QueryExecution']:
                stats = response['QueryExecution']['Statistics']
                if 'EngineExecutionTimeInMillis' in stats:
                    result.execution_time_ms = stats['EngineExecutionTimeInMillis']
            
            # Get results
            results_paginator = athena_client.get_paginator('get_query_results')
            result_pages = results_paginator.paginate(QueryExecutionId=query_execution_id)
            
            # Process first page to get column info
            first_page = next(iter(result_pages))
            column_info = first_page['ResultSet']['ResultSetMetadata']['ColumnInfo']
            result.columns = [col['Name'] for col in column_info]
            
            # Process all rows
            all_rows = []
            
            # Add rows from first page
            if 'Rows' in first_page['ResultSet']:
                # Skip header row
                rows = first_page['ResultSet']['Rows'][1:] if first_page['ResultSet']['Rows'] else []
                for row in rows:
                    row_data = {}
                    for i, data in enumerate(row['Data']):
                        # Handle null values
                        if 'VarCharValue' in data:
                            row_data[result.columns[i]] = data['VarCharValue']
                        else:
                            row_data[result.columns[i]] = None
                    all_rows.append(row_data)
            
            # Process remaining pages
            for page in result_pages:
                if 'Rows' in page['ResultSet']:
                    for row in page['ResultSet']['Rows']:
                        row_data = {}
                        for i, data in enumerate(row['Data']):
                            # Handle null values
                            if 'VarCharValue' in data:
                                row_data[result.columns[i]] = data['VarCharValue']
                            else:
                                row_data[result.columns[i]] = None
                        all_rows.append(row_data)
            
            result.data = all_rows
            result.row_count = len(all_rows)
            
        elif state == 'FAILED':
            # Get error message if query failed
            response = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
            if 'QueryExecution' in response and 'Status' in response['QueryExecution']:
                status = response['QueryExecution']['Status']
                if 'StateChangeReason' in status:
                    result.error_message = status['StateChangeReason']
        
        return result
        
    except Exception as e:
        # Handle any exceptions
        return AthenaQueryResult(
            query_id="error",
            query=query,
            status="ERROR",
            error_message=str(e)
        )


@tool
def generate_sql_query(
    natural_language_query: str,
    database_name: str,
    table_name: str
) -> str:
    """
    Generate a SQL query from a natural language description.
    This is a helper function that constructs a simple SQL query based on the natural language request.
    For complex queries, the agent should construct the SQL directly.
    
    Args:
        natural_language_query: Natural language description of the query
        database_name: The database to query
        table_name: The table to query
    
    Returns:
        A SQL query string
    """
    # This is a simplified implementation that generates basic SQL queries
    # In a real implementation, this would use a more sophisticated approach
    
    # Detect if this is a simple "select all" query
    if any(keyword in natural_language_query.lower() for keyword in ["all", "everything", "show me"]):
        return f"SELECT * FROM {database_name}.{table_name} LIMIT 10"
    
    # Detect if this is a count query
    if any(keyword in natural_language_query.lower() for keyword in ["count", "how many"]):
        return f"SELECT COUNT(*) AS count FROM {database_name}.{table_name}"
    
    # Detect if this is a filter query
    filter_keywords = ["where", "filter", "only", "with"]
    if any(keyword in natural_language_query.lower() for keyword in filter_keywords):
        # This is a very simplified approach - in reality, you'd need more sophisticated NLP
        # to extract the filter conditions
        return f"SELECT * FROM {database_name}.{table_name} WHERE {natural_language_query.split('where')[-1].strip()} LIMIT 10"
    
    # Default to a simple select
    return f"SELECT * FROM {database_name}.{table_name} LIMIT 10"


@tool
def list_query_executions(max_results: int = 10) -> List[Dict[str, Any]]:
    """
    List recent query executions in Athena.
    
    Args:
        max_results: Maximum number of results to return (default: 10)
    
    Returns:
        A list of query execution information
    """
    # Initialize Athena client
    athena_client = boto3.client('athena')
    
    try:
        # Get list of query execution IDs
        response = athena_client.list_query_executions(
            MaxResults=max_results
        )
        
        query_execution_ids = response.get('QueryExecutionIds', [])
        
        # Get details for each query execution
        query_executions = []
        for query_id in query_execution_ids:
            execution = athena_client.get_query_execution(QueryExecutionId=query_id)
            
            # Extract relevant information
            query_execution = execution.get('QueryExecution', {})
            status = query_execution.get('Status', {})
            statistics = query_execution.get('Statistics', {})
            
            query_executions.append({
                'query_id': query_id,
                'query': query_execution.get('Query', ''),
                'status': status.get('State', ''),
                'submission_time': str(query_execution.get('SubmissionDateTime', '')),
                'completion_time': str(query_execution.get('CompletionDateTime', '')),
                'execution_time_ms': statistics.get('EngineExecutionTimeInMillis'),
                'data_scanned_bytes': statistics.get('DataScannedInBytes'),
                'database': query_execution.get('QueryExecutionContext', {}).get('Database', '')
            })
        
        return query_executions
        
    except Exception as e:
        raise ValueError(f"Error listing query executions: {str(e)}")


@tool
def get_query_results(query_execution_id: str) -> AthenaQueryResult:
    """
    Get results for a previously executed Athena query.
    
    Args:
        query_execution_id: The ID of the query execution to retrieve results for
    
    Returns:
        An AthenaQueryResult containing query results
    """
    # Initialize Athena client
    athena_client = boto3.client('athena')
    
    try:
        # Get query execution details
        execution = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
        query_execution = execution.get('QueryExecution', {})
        status = query_execution.get('Status', {}).get('State', '')
        query = query_execution.get('Query', '')
        
        # Initialize result
        result = AthenaQueryResult(
            query_id=query_execution_id,
            query=query,
            status=status
        )
        
        # If query failed, get error message
        if status == 'FAILED':
            result.error_message = query_execution.get('Status', {}).get('StateChangeReason', '')
            return result
        
        # If query not completed, return status
        if status != 'SUCCEEDED':
            return result
        
        # Get execution time
        if 'Statistics' in query_execution:
            stats = query_execution['Statistics']
            if 'EngineExecutionTimeInMillis' in stats:
                result.execution_time_ms = stats['EngineExecutionTimeInMillis']
        
        # Get results
        results_paginator = athena_client.get_paginator('get_query_results')
        result_pages = results_paginator.paginate(QueryExecutionId=query_execution_id)
        
        # Process first page to get column info
        first_page = next(iter(result_pages))
        column_info = first_page['ResultSet']['ResultSetMetadata']['ColumnInfo']
        result.columns = [col['Name'] for col in column_info]
        
        # Process all rows
        all_rows = []
        
        # Add rows from first page
        if 'Rows' in first_page['ResultSet']:
            # Skip header row
            rows = first_page['ResultSet']['Rows'][1:] if first_page['ResultSet']['Rows'] else []
            for row in rows:
                row_data = {}
                for i, data in enumerate(row['Data']):
                    # Handle null values
                    if 'VarCharValue' in data:
                        row_data[result.columns[i]] = data['VarCharValue']
                    else:
                        row_data[result.columns[i]] = None
                all_rows.append(row_data)
        
        # Process remaining pages
        for page in result_pages:
            if 'Rows' in page['ResultSet']:
                for row in page['ResultSet']['Rows']:
                    row_data = {}
                    for i, data in enumerate(row['Data']):
                        # Handle null values
                        if 'VarCharValue' in data:
                            row_data[result.columns[i]] = data['VarCharValue']
                        else:
                            row_data[result.columns[i]] = None
                    all_rows.append(row_data)
        
        result.data = all_rows
        result.row_count = len(all_rows)
        
        return result
        
    except Exception as e:
        # Handle any exceptions
        return AthenaQueryResult(
            query_id=query_execution_id,
            query="",
            status="ERROR",
            error_message=str(e)
        )
