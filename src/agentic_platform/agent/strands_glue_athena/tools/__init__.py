"""
Tools for the Strands Glue/Athena agent.
"""
# Re-export all tools
from .glue_tools import (
    search_glue_catalog,
    get_table_details,
    list_databases,
    list_tables,
    GlueTable,
    GlueSearchResult
)

from .athena_tools import (
    run_athena_query,
    generate_sql_query,
    list_query_executions,
    get_query_results,
    AthenaQueryResult
)

__all__ = [
    'search_glue_catalog',
    'get_table_details',
    'list_databases',
    'list_tables',
    'GlueTable',
    'GlueSearchResult',
    'run_athena_query',
    'generate_sql_query',
    'list_query_executions',
    'get_query_results',
    'AthenaQueryResult'
]
