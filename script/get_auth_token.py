# get_auth_token.py
import boto3
import os
import json
import argparse
import sys

def get_config_from_ssm(environment="dev", region=None):
    """Fetch configuration from SSM Parameter Store"""
    ssm = boto3.client('ssm', region_name=region)
    param_name = f"/agentic-platform/config/{environment}"
    
    try:
        response = ssm.get_parameter(Name=param_name, WithDecryption=True)
        return json.loads(response['Parameter']['Value'])
    except Exception as e:
        print(f"Error fetching config from SSM: {e}")
        sys.exit(1)

def get_token(username=None, password=None, environment="dev", region=None):
    """Get Cognito access token using provided or SSM credentials"""
    config = get_config_from_ssm(environment, region)
    
    client_id = config.get('COGNITO_USER_CLIENT_ID')
    if not client_id:
        print("Error: COGNITO_USER_CLIENT_ID not found in SSM config")
        sys.exit(1)
    
    if not username or not password:
        print("Error: Username and password are required")
        sys.exit(1)
    
    try:
        # Create Cognito client
        client = boto3.client('cognito-idp', region_name=region)
        
        # Authenticate with username and password
        response = client.initiate_auth(
            ClientId=client_id,
            AuthFlow='USER_PASSWORD_AUTH',
            AuthParameters={
                'USERNAME': username,
                'PASSWORD': password
            }
        )
        
        # Extract the token
        token = response['AuthenticationResult']['AccessToken']
        
        # Print the token
        print("\nAccess Token (for Authorization: Bearer):")
        print(f"Bearer {token}")
        
        # Show how to use it with curl
        print("\nCurl example:")
        print(f'curl -H "Authorization: Bearer {token}" https://your-api-endpoint/health')
        
        
        return token
        
    except Exception as e:
        print(f"Error getting token: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    # Add command line arguments
    parser = argparse.ArgumentParser(description='Get Cognito access token')
    parser.add_argument('--username', required=True, help='Cognito username')
    parser.add_argument('--password', required=True, help='Cognito password')
    parser.add_argument('--environment', default='dev', help='Environment (default: dev)')
    parser.add_argument('--region', help='AWS region')
    parser.add_argument('--quiet', action='store_true', help='Only output the token')
    
    args = parser.parse_args()
    
    # Get token
    token = get_token(args.username, args.password, args.environment, args.region)
    
    # If quiet mode, just print the token
    if args.quiet:
        print(token)