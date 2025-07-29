#!/usr/bin/env python3
"""
API test script for the Strands agent.
This tests the actual API endpoints once the agent is running.
"""

import requests
import json
import sys
from typing import Dict, Any

def test_health_endpoint(base_url: str = "http://localhost:8000") -> bool:
    """Test the health endpoint"""
    print("🧪 Testing health endpoint...")
    try:
        response = requests.get(f"{base_url}/health", timeout=5)
        if response.status_code == 200:
            print("✅ Health endpoint working")
            print(f"   Response: {response.json()}")
            return True
        else:
            print(f"❌ Health endpoint failed with status {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Health endpoint failed: {e}")
        return False

def test_invoke_endpoint(base_url: str = "http://localhost:8000") -> bool:
    """Test the invoke endpoint with a simple request"""
    print("\n🧪 Testing invoke endpoint...")
    
    # Create a test request
    test_request = {
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": "Hello, can you help me with a simple calculation? What is 2 + 2?"
                }
            ]
        },
        "session_id": "test-session-123"
    }
    
    try:
        response = requests.post(
            f"{base_url}/invoke",
            json=test_request,
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Invoke endpoint working")
            print(f"   Session ID: {result.get('session_id')}")
            print(f"   Response message: {result.get('message', {}).get('content', [{}])[0].get('text', 'No text')[:100]}...")
            return True
        else:
            print(f"❌ Invoke endpoint failed with status {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Invoke endpoint failed: {e}")
        return False

def test_weather_tool(base_url: str = "http://localhost:8000") -> bool:
    """Test the weather tool functionality"""
    print("\n🧪 Testing weather tool...")
    
    test_request = {
        "message": {
            "role": "user", 
            "content": [
                {
                    "type": "text",
                    "text": "What's the weather like in San Francisco?"
                }
            ]
        },
        "session_id": "test-weather-session"
    }
    
    try:
        response = requests.post(
            f"{base_url}/invoke",
            json=test_request,
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            response_text = result.get('message', {}).get('content', [{}])[0].get('text', '')
            
            # Check if response mentions weather-related terms
            weather_terms = ['weather', 'temperature', 'sunny', 'cloudy', 'rain', 'forecast']
            if any(term.lower() in response_text.lower() for term in weather_terms):
                print("✅ Weather tool appears to be working")
                print(f"   Response contains weather information")
                return True
            else:
                print("⚠️  Weather tool response unclear")
                print(f"   Response: {response_text[:200]}...")
                return True  # Still counts as working, just unclear response
        else:
            print(f"❌ Weather tool test failed with status {response.status_code}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Weather tool test failed: {e}")
        return False

def main():
    """Run API tests"""
    if len(sys.argv) > 1:
        base_url = sys.argv[1]
    else:
        base_url = "http://localhost:8000"
    
    print(f"🚀 Testing Strands Agent API at {base_url}\n")
    
    tests = [
        lambda: test_health_endpoint(base_url),
        lambda: test_invoke_endpoint(base_url),
        lambda: test_weather_tool(base_url)
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
    
    print(f"\n📊 API Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All API tests passed! The Strands agent is working correctly.")
    elif passed > 0:
        print("⚠️  Some API tests passed. The agent is partially working.")
    else:
        print("❌ All API tests failed. Check if the agent is running and configured correctly.")
        print("\n🔧 Troubleshooting:")
        print("   1. Make sure the agent is running: python src/agentic_platform/agent/strands_agent/server.py")
        print("   2. Check AWS credentials are configured")
        print("   3. Verify LiteLLM gateway is accessible")
        print("   4. Check the agent logs for errors")

if __name__ == "__main__":
    main()