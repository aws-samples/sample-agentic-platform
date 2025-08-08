"""
Tools for interacting with AWS Glue catalog.
"""
import boto3
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from thefuzz import fuzz, process
from strands import tool


class GlueTable(BaseModel):
    """Representation of a table in the AWS Glue catalog."""
    database_name: str
    table_name: str
    description: Optional[str] = None
    columns: List[Dict[str, str]] = []
    location: Optional[str] = None
    table_type: Optional[str] = None
    create_time: Optional[str] = None
    last_access_time: Optional[str] = None
    match_score: Optional[float] = None


class GlueSearchResult(BaseModel):
    """Result of a search in the AWS Glue catalog."""
    tables: List[GlueTable]
    query: str
    total_tables_searched: int


@tool
def search_glue_catalog(
    query: str,
    max_results: int = 5,
    min_score: float = 60.0
) -> GlueSearchResult:
    """
    Search for tables in the AWS Glue catalog based on table name, columns, and description.
    
    Args:
        query: The search query to match against table names, columns, and descriptions
        max_results: Maximum number of results to return (default: 5)
        min_score: Minimum similarity score (0-100) for results (default: 60.0)
    
    Returns:
        A GlueSearchResult containing matching tables and search metadata
    """
    # Initialize AWS Glue client
    glue_client = boto3.client('glue')
    
    # Get all databases
    databases_response = glue_client.get_databases()
    databases = databases_response.get('DatabaseList', [])
    
    all_tables = []
    total_tables = 0
    
    # For each database, get all tables
    for database in databases:
        database_name = database['Name']
        
        # Get tables for this database
        paginator = glue_client.get_paginator('get_tables')
        for page in paginator.paginate(DatabaseName=database_name):
            tables = page.get('TableList', [])
            total_tables += len(tables)
            
            # Process each table
            for table in tables:
                table_name = table.get('Name', '')
                description = table.get('Description', '')
                
                # Extract column information
                columns = []
                if 'StorageDescriptor' in table and 'Columns' in table['StorageDescriptor']:
                    columns = [
                        {
                            'name': col.get('Name', ''),
                            'type': col.get('Type', ''),
                            'comment': col.get('Comment', '')
                        }
                        for col in table['StorageDescriptor']['Columns']
                    ]
                
                # Create a searchable text from table metadata
                column_names = ' '.join([col['name'] for col in columns])
                column_comments = ' '.join([col['comment'] for col in columns if col['comment']])
                searchable_text = f"{table_name} {description} {column_names} {column_comments}".lower()
                
                # Calculate similarity score
                score = fuzz.token_set_ratio(query.lower(), searchable_text)
                
                # If score meets threshold, add to results
                if score >= min_score:
                    location = table.get('StorageDescriptor', {}).get('Location')
                    table_type = table.get('TableType')
                    create_time = table.get('CreateTime')
                    last_access_time = table.get('LastAccessTime')
                    
                    all_tables.append(GlueTable(
                        database_name=database_name,
                        table_name=table_name,
                        description=description,
                        columns=columns,
                        location=location,
                        table_type=table_type,
                        create_time=str(create_time) if create_time else None,
                        last_access_time=str(last_access_time) if last_access_time else None,
                        match_score=score
                    ))
    
    # Sort tables by score (descending) and limit results
    sorted_tables = sorted(all_tables, key=lambda x: x.match_score or 0, reverse=True)
    limited_tables = sorted_tables[:max_results]
    
    return GlueSearchResult(
        tables=limited_tables,
        query=query,
        total_tables_searched=total_tables
    )


@tool
def get_table_details(database_name: str, table_name: str) -> GlueTable:
    """
    Get detailed information about a specific table in the AWS Glue catalog.
    
    Args:
        database_name: The name of the database containing the table
        table_name: The name of the table to retrieve details for
    
    Returns:
        A GlueTable containing detailed information about the specified table
    """
    # Initialize AWS Glue client
    glue_client = boto3.client('glue')
    
    try:
        # Get table details
        response = glue_client.get_table(
            DatabaseName=database_name,
            Name=table_name
        )
        
        table = response.get('Table', {})
        
        # Extract column information
        columns = []
        if 'StorageDescriptor' in table and 'Columns' in table['StorageDescriptor']:
            columns = [
                {
                    'name': col.get('Name', ''),
                    'type': col.get('Type', ''),
                    'comment': col.get('Comment', '')
                }
                for col in table['StorageDescriptor']['Columns']
            ]
        
        # Create and return GlueTable object
        return GlueTable(
            database_name=database_name,
            table_name=table_name,
            description=table.get('Description', ''),
            columns=columns,
            location=table.get('StorageDescriptor', {}).get('Location'),
            table_type=table.get('TableType'),
            create_time=str(table.get('CreateTime')) if table.get('CreateTime') else None,
            last_access_time=str(table.get('LastAccessTime')) if table.get('LastAccessTime') else None
        )
        
    except glue_client.exceptions.EntityNotFoundException:
        raise ValueError(f"Table {table_name} not found in database {database_name}")
    except Exception as e:
        raise ValueError(f"Error retrieving table details: {str(e)}")


@tool
def list_databases() -> List[str]:
    """
    List all databases in the AWS Glue catalog.
    
    Returns:
        A list of database names
    """
    # Initialize AWS Glue client
    glue_client = boto3.client('glue')
    
    try:
        # Get all databases
        databases_response = glue_client.get_databases()
        databases = databases_response.get('DatabaseList', [])
        
        # Extract database names
        database_names = [db['Name'] for db in databases]
        
        return database_names
        
    except Exception as e:
        raise ValueError(f"Error listing databases: {str(e)}")


@tool
def list_tables(database_name: str) -> List[str]:
    """
    List all tables in a specific AWS Glue database.
    
    Args:
        database_name: The name of the database to list tables from
    
    Returns:
        A list of table names
    """
    # Initialize AWS Glue client
    glue_client = boto3.client('glue')
    
    try:
        # Get tables for this database
        tables = []
        paginator = glue_client.get_paginator('get_tables')
        for page in paginator.paginate(DatabaseName=database_name):
            tables.extend(page.get('TableList', []))
        
        # Extract table names
        table_names = [table['Name'] for table in tables]
        
        return table_names
        
    except glue_client.exceptions.EntityNotFoundException:
        raise ValueError(f"Database {database_name} not found")
    except Exception as e:
        raise ValueError(f"Error listing tables: {str(e)}")
