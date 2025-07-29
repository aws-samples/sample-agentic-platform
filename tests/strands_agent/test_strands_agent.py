#!/usr/bin/env python3
"""
Simple test script for the Strands agent implementation.
This tests the code structure and syntax without requiring dependencies.
"""

import sys
import os
import ast
import importlib.util
from pathlib import Path

def test_python_syntax():
    """Test that all Python files have valid syntax"""
    print("🧪 Testing Python syntax...")
    
    # Get the project root directory (three levels up from tests/strands_agent)
    project_root = Path(__file__).parent.parent.parent
    strands_dir = project_root / "src/agentic_platform/agent/strands_agent"
    python_files = list(strands_dir.glob("*.py"))
    
    if not python_files:
        print("❌ No Python files found in strands_agent directory")
        return False
    
    all_valid = True
    for py_file in python_files:
        try:
            with open(py_file, 'r') as f:
                source = f.read()
            ast.parse(source)
            print(f"✅ {py_file.name} - syntax valid")
        except SyntaxError as e:
            print(f"❌ {py_file.name} - syntax error: {e}")
            all_valid = False
        except Exception as e:
            print(f"❌ {py_file.name} - error: {e}")
            all_valid = False
    
    return all_valid

def test_file_structure():
    """Test that all required files exist"""
    print("\n🧪 Testing file structure...")
    
    # Get the project root directory
    project_root = Path(__file__).parent.parent.parent
    
    required_files = [
        project_root / "src/agentic_platform/agent/strands_agent/strands_agent.py",
        project_root / "src/agentic_platform/agent/strands_agent/strands_agent_controller.py", 
        project_root / "src/agentic_platform/agent/strands_agent/server.py",
        project_root / "src/agentic_platform/agent/strands_agent/requirements.txt",
        project_root / "docker/strands-agent/Dockerfile",
        project_root / "k8s/helm/values/applications/strands-agent-values.yaml"
    ]
    
    all_exist = True
    for file_path in required_files:
        if file_path.exists():
            print(f"✅ {file_path.relative_to(project_root)}")
        else:
            print(f"❌ Missing: {file_path.relative_to(project_root)}")
            all_exist = False
    
    return all_exist

def test_imports_structure():
    """Test that import statements are structured correctly"""
    print("\n🧪 Testing import structure...")
    
    try:
        # Test strands_agent.py imports
        project_root = Path(__file__).parent.parent.parent
        strands_agent_file = project_root / "src/agentic_platform/agent/strands_agent/strands_agent.py"
        with open(strands_agent_file, 'r') as f:
            content = f.read()
            
        # Check for key imports
        required_imports = [
            "from strands import Agent as StrandsAgent",
            "from strands.models.litellm import LiteLLMModel",
            "from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse",
            "from agentic_platform.core.client.memory_gateway.memory_gateway_client import MemoryGatewayClient"
        ]
        
        missing_imports = []
        for imp in required_imports:
            if imp not in content:
                missing_imports.append(imp)
        
        if missing_imports:
            print("❌ Missing imports:")
            for imp in missing_imports:
                print(f"   - {imp}")
            return False
        else:
            print("✅ All required imports present")
            return True
            
    except Exception as e:
        print(f"❌ Error checking imports: {e}")
        return False

def test_class_structure():
    """Test that classes have required methods"""
    print("\n🧪 Testing class structure...")
    
    try:
        # Parse the strands_agent.py file
        project_root = Path(__file__).parent.parent.parent
        strands_agent_file = project_root / "src/agentic_platform/agent/strands_agent/strands_agent.py"
        with open(strands_agent_file, 'r') as f:
            tree = ast.parse(f.read())
        
        # Find StrandsAgentWrapper class
        wrapper_class = None
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == "StrandsAgentWrapper":
                wrapper_class = node
                break
        
        if not wrapper_class:
            print("❌ StrandsAgentWrapper class not found")
            return False
        
        # Check for required methods
        methods = [node.name for node in wrapper_class.body if isinstance(node, ast.FunctionDef)]
        required_methods = ["__init__", "invoke"]
        
        missing_methods = [m for m in required_methods if m not in methods]
        if missing_methods:
            print(f"❌ Missing methods in StrandsAgentWrapper: {missing_methods}")
            return False
        
        print("✅ StrandsAgentWrapper class structure valid")
        
        # Test controller structure
        controller_file = project_root / "src/agentic_platform/agent/strands_agent/strands_agent_controller.py"
        with open(controller_file, 'r') as f:
            tree = ast.parse(f.read())
        
        controller_class = None
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == "StrandsAgentController":
                controller_class = node
                break
        
        if not controller_class:
            print("❌ StrandsAgentController class not found")
            return False
        
        methods = [node.name for node in controller_class.body if isinstance(node, ast.FunctionDef)]
        required_methods = ["invoke", "_get_agent"]
        
        missing_methods = [m for m in required_methods if m not in methods]
        if missing_methods:
            print(f"❌ Missing methods in StrandsAgentController: {missing_methods}")
            return False
        
        print("✅ StrandsAgentController class structure valid")
        return True
        
    except Exception as e:
        print(f"❌ Error checking class structure: {e}")
        return False

def test_docker_structure():
    """Test Docker configuration"""
    print("\n🧪 Testing Docker configuration...")
    
    try:
        project_root = Path(__file__).parent.parent.parent
        dockerfile_path = project_root / "docker/strands-agent/Dockerfile"
        with open(dockerfile_path, 'r') as f:
            dockerfile_content = f.read()
        
        required_elements = [
            "FROM python:",
            "COPY src/agentic_platform/agent/strands_agent/requirements.txt",
            "RUN pip install",
            "CMD [\"uvicorn\", \"agentic_platform.agent.strands_agent.server:app\"",
            "EXPOSE 8000"
        ]
        
        missing_elements = []
        for element in required_elements:
            if element not in dockerfile_content:
                missing_elements.append(element)
        
        if missing_elements:
            print("❌ Missing Dockerfile elements:")
            for element in missing_elements:
                print(f"   - {element}")
            return False
        
        print("✅ Dockerfile structure valid")
        return True
        
    except Exception as e:
        print(f"❌ Error checking Dockerfile: {e}")
        return False

def test_requirements():
    """Test requirements.txt"""
    print("\n🧪 Testing requirements.txt...")
    
    try:
        project_root = Path(__file__).parent.parent.parent
        requirements_file = project_root / "src/agentic_platform/agent/strands_agent/requirements.txt"
        with open(requirements_file, 'r') as f:
            requirements = f.read()
        
        required_packages = [
            "strands-agents",
            "fastapi",
            "uvicorn"
        ]
        
        missing_packages = []
        for package in required_packages:
            if package not in requirements:
                missing_packages.append(package)
        
        if missing_packages:
            print(f"❌ Missing packages in requirements.txt: {missing_packages}")
            return False
        
        print("✅ Requirements.txt valid")
        return True
        
    except Exception as e:
        print(f"❌ Error checking requirements.txt: {e}")
        return False

def main():
    """Run all tests"""
    print("🚀 Starting Strands Agent Structure Tests\n")
    print("This tests the code structure without requiring dependencies to be installed.\n")
    
    tests = [
        test_file_structure,
        test_python_syntax,
        test_imports_structure,
        test_class_structure,
        test_docker_structure,
        test_requirements
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
    
    print(f"\n📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All structural tests passed! The Strands agent is properly implemented.")
        print("\n📝 Next steps for full testing:")
        print("   1. Install dependencies: pip install -r src/agentic_platform/agent/strands_agent/requirements.txt")
        print("   2. Set up AWS credentials and LiteLLM gateway")
        print("   3. Test locally: python src/agentic_platform/agent/strands_agent/server.py")
        print("   4. Deploy to EKS: ./deploy/deploy-application.sh strands-agent --build")
        print("   5. Test with actual API calls")
        print("\n🔧 For immediate testing without full setup:")
        print("   - Run the notebook examples in labs/module3/notebooks/5_agent_frameworks.ipynb")
        print("   - Use the deployment scripts to build and deploy to EKS")
    else:
        print("❌ Some structural tests failed. Check the errors above.")
        sys.exit(1)

if __name__ == "__main__":
    main()