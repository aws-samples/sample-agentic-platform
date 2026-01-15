#!/usr/bin/env python3
import boto3
import json
import argparse
import sys
import random
import string

def generate_random_string(length=8):
    """Generate a random string of letters and digits"""
    return ''.join(random.choice(string.ascii_lowercase + string.digits) for _ in range(length))

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

def create_admin_user(email=None, password=None, environment="dev", region=None):
    """Create user using Cognito admin APIs"""
    config = get_config_from_ssm(environment, region)
    
    user_pool_id = config.get('COGNITO_USER_POOL_ID')
    if not user_pool_id:
        print("Error: COGNITO_USER_POOL_ID not found in SSM config")
        sys.exit(1)
    
    email = email or f"test-{generate_random_string(8)}@example.com"
    password = password or generate_random_string(12) + "Aa1!"
    
    cognito = boto3.client('cognito-idp', region_name=region)
    
    try:
        print(f"Creating user: {email}")
        cognito.admin_create_user(
            UserPoolId=user_pool_id,
            Username=email,
            TemporaryPassword=password,
            UserAttributes=[
                {'Name': 'email', 'Value': email},
                {'Name': 'email_verified', 'Value': 'true'}
            ],
            MessageAction='SUPPRESS'
        )
        
        cognito.admin_set_user_password(
            UserPoolId=user_pool_id,
            Username=email,
            Password=password,
            Permanent=True
        )
        
        print(f"\nUser created successfully!")
        print(f"Email: {email}")
        print(f"Password: {password}")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Create Cognito user via admin API')
    parser.add_argument('--email', help='Email address')
    parser.add_argument('--password', help='Password')
    parser.add_argument('--environment', default='dev', help='Environment (default: dev)')
    parser.add_argument('--region', help='AWS region')
    
    args = parser.parse_args()
    create_admin_user(args.email, args.password, args.environment, args.region)
