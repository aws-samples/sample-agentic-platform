#!/usr/bin/env python3
"""
Test runner for Strands agent tests.
Runs all available tests in the correct order.
"""

import sys
import subprocess
import os
from pathlib import Path

def run_structural_tests():
    """Run structural tests"""
    print("🏗️  Running Structural Tests...")
    print("=" * 50)
    
    result = subprocess.run([
        sys.executable, 
        "tests/strands_agent/test_strands_agent.py"
    ], capture_output=False)
    
    return result.returncode == 0

def run_api_tests(base_url="http://localhost:8000"):
    """Run API tests"""
    print("\n🌐 Running API Tests...")
    print("=" * 50)
    print(f"Testing against: {base_url}")
    
    result = subprocess.run([
        sys.executable, 
        "tests/strands_agent/test_strands_api.py",
        base_url
    ], capture_output=False)
    
    return result.returncode == 0

def check_agent_running(base_url="http://localhost:8000"):
    """Check if agent is running"""
    try:
        import requests
        response = requests.get(f"{base_url}/health", timeout=2)
        return response.status_code == 200
    except:
        return False

def main():
    """Run all tests"""
    print("🚀 Strands Agent Test Runner")
    print("=" * 50)
    
    # Parse command line arguments
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
    
    # Always run structural tests first
    structural_passed = run_structural_tests()
    
    if not structural_passed:
        print("\n❌ Structural tests failed. Fix these issues before proceeding.")
        sys.exit(1)
    
    # Check if we should run API tests
    if base_url != "http://localhost:8000" or check_agent_running(base_url):
        api_passed = run_api_tests(base_url)
    else:
        print(f"\n⚠️  Agent not running at {base_url}")
        print("Skipping API tests. To run API tests:")
        print("1. Start the agent: python src/agentic_platform/agent/strands_agent/server.py")
        print("2. Run: python tests/strands_agent/run_tests.py")
        print("3. Or test remote: python tests/strands_agent/run_tests.py https://your-url.com")
        api_passed = None
    
    # Summary
    print("\n" + "=" * 50)
    print("📊 TEST SUMMARY")
    print("=" * 50)
    print(f"🏗️  Structural Tests: {'✅ PASSED' if structural_passed else '❌ FAILED'}")
    
    if api_passed is not None:
        print(f"🌐 API Tests: {'✅ PASSED' if api_passed else '❌ FAILED'}")
    else:
        print("🌐 API Tests: ⏭️  SKIPPED")
    
    if structural_passed and (api_passed is None or api_passed):
        print("\n🎉 All available tests passed!")
        print("\n📝 Next steps:")
        if api_passed is None:
            print("   - Start the agent and run API tests")
        print("   - Test notebook examples: labs/module3/notebooks/5_agent_frameworks.ipynb")
        print("   - Deploy to EKS: ./deploy/deploy-application.sh strands-agent --build")
    else:
        print("\n❌ Some tests failed. Check the output above for details.")
        sys.exit(1)

if __name__ == "__main__":
    main()