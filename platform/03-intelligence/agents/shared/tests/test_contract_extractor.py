"""
Unit tests for contract_extractor module.
"""

import pytest
from pathlib import Path
import tempfile
import os

from contract_extractor import (
    extract_contract_boundary,
    FileType,
    ContractExtractionError
)


class TestYAMLExtractor:
    """Tests for YAML contract extraction."""
    
    def test_extract_crossplane_yaml(self, tmp_path):
        """Test extracting parameters from Crossplane YAML file."""
        yaml_content = """
apiVersion: example.com/v1
kind: WebService
metadata:
  name: test-service
  namespace: default
spec:
  forProvider:
    region: us-east-1
    instanceType: t3.micro
    tags:
      environment: production
      team: platform
  compositeTypeRef:
    apiVersion: example.com/v1
    kind: XWebService
status:
  ready: true
"""
        yaml_file = tmp_path / "test.yaml"
        yaml_file.write_text(yaml_content)
        
        boundary = extract_contract_boundary(str(yaml_file))
        
        assert boundary.file_type == FileType.YAML
        assert len(boundary.parameters) > 0
        
        # Check for specific parameters
        param_names = [p.name for p in boundary.parameters]
        assert "region" in param_names
        assert "instanceType" in param_names
        
        # Check metadata
        assert "name" in boundary.metadata
        assert boundary.metadata["name"] == "test-service"
    
    def test_yaml_ignores_status(self, tmp_path):
        """Test that status fields are ignored."""
        yaml_content = """
apiVersion: v1
kind: Test
spec:
  forProvider:
    value: test
status:
  condition: ready
  phase: running
"""
        yaml_file = tmp_path / "test.yaml"
        yaml_file.write_text(yaml_content)
        
        boundary = extract_contract_boundary(str(yaml_file))
        
        # Status should not be in parameters
        param_names = [p.name for p in boundary.parameters]
        assert "status" not in param_names
        assert "condition" not in param_names


class TestPythonExtractor:
    """Tests for Python contract extraction."""
    
    def test_extract_function_signature(self, tmp_path):
        """Test extracting function signatures from Python file."""
        python_content = """
def process_data(input_file: str, output_file: str, verbose: bool = False) -> int:
    '''Process data from input to output.'''
    return 0

async def fetch_data(url: str) -> dict:
    '''Fetch data from URL.'''
    return {}
"""
        python_file = tmp_path / "test.py"
        python_file.write_text(python_content)
        
        boundary = extract_contract_boundary(str(python_file))
        
        assert boundary.file_type == FileType.PYTHON
        assert len(boundary.parameters) > 0
        
        # Check for function parameters
        param_names = [p.name for p in boundary.parameters]
        assert "process_data.input_file" in param_names
        assert "process_data.output_file" in param_names
        assert "fetch_data.url" in param_names
        
        # Check return types
        assert "process_data.return" in param_names
        assert "fetch_data.return" in param_names
    
    def test_extract_dataclass(self, tmp_path):
        """Test extracting dataclass definitions."""
        python_content = """
from dataclasses import dataclass

@dataclass
class Config:
    host: str
    port: int
    debug: bool = False
"""
        python_file = tmp_path / "test.py"
        python_file.write_text(python_content)
        
        boundary = extract_contract_boundary(str(python_file))
        
        param_names = [p.name for p in boundary.parameters]
        assert "Config.host" in param_names
        assert "Config.port" in param_names
        assert "Config.debug" in param_names
    
    def test_ignores_private_methods(self, tmp_path):
        """Test that private methods are ignored."""
        python_content = """
def public_method(arg: str) -> None:
    pass

def _private_method(arg: str) -> None:
    pass
"""
        python_file = tmp_path / "test.py"
        python_file.write_text(python_content)
        
        boundary = extract_contract_boundary(str(python_file))
        
        param_names = [p.name for p in boundary.parameters]
        assert "public_method.arg" in param_names
        assert "_private_method.arg" not in param_names


class TestRegoExtractor:
    """Tests for Rego contract extraction."""
    
    def test_extract_rego_rules(self, tmp_path):
        """Test extracting rule names from Rego file."""
        rego_content = """
package example.authz

import data.users

default allow = false

allow {
    input.user == "admin"
}

deny[msg] {
    not allow
    msg := "Access denied"
}
"""
        rego_file = tmp_path / "test.rego"
        rego_file.write_text(rego_content)
        
        boundary = extract_contract_boundary(str(rego_file))
        
        assert boundary.file_type == FileType.REGO
        assert "package" in boundary.metadata
        assert boundary.metadata["package"] == "example.authz"
        
        param_names = [p.name for p in boundary.parameters]
        assert "allow" in param_names
        assert "deny" in param_names
    
    def test_extract_input_references(self, tmp_path):
        """Test extracting input references from Rego."""
        rego_content = """
package test

allow {
    input.user.role == "admin"
    input.resource.type == "secret"
}
"""
        rego_file = tmp_path / "test.rego"
        rego_file.write_text(rego_content)
        
        boundary = extract_contract_boundary(str(rego_file))
        
        param_names = [p.name for p in boundary.parameters]
        assert "input.user.role" in param_names
        assert "input.resource.type" in param_names


class TestMarkdownExtractor:
    """Tests for Markdown contract extraction."""
    
    def test_extract_runbook_sections(self, tmp_path):
        """Test extracting sections from Markdown runbook."""
        markdown_content = """
# Database Connection Issue

## Symptoms

- Application cannot connect to database
- Connection timeout errors in logs

## Diagnosis

1. Check database server status
2. Verify network connectivity
3. Review connection string

## Resolution

1. Restart database service
2. Update connection pool settings
3. Monitor for 24 hours
"""
        md_file = tmp_path / "runbook.md"
        md_file.write_text(markdown_content)
        
        boundary = extract_contract_boundary(str(md_file))
        
        assert boundary.file_type == FileType.MARKDOWN
        assert "title" in boundary.metadata
        assert boundary.metadata["title"] == "Database Connection Issue"
        
        param_names = [p.name for p in boundary.parameters]
        assert "Symptoms" in param_names
        assert "Diagnosis" in param_names
        assert "Resolution" in param_names
    
    def test_ignores_anecdotes(self, tmp_path):
        """Test that non-section content is ignored."""
        markdown_content = """
# Issue Title

This is some background information that should be ignored.

## Symptoms

Actual symptoms here.

Some more anecdotal information between sections.

## Resolution

Steps to resolve.
"""
        md_file = tmp_path / "runbook.md"
        md_file.write_text(markdown_content)
        
        boundary = extract_contract_boundary(str(md_file))
        
        # Should only have section parameters
        param_names = [p.name for p in boundary.parameters]
        assert len(param_names) == 2
        assert "Symptoms" in param_names
        assert "Resolution" in param_names


class TestErrorHandling:
    """Tests for error handling."""
    
    def test_file_not_found(self):
        """Test error when file doesn't exist."""
        with pytest.raises(ContractExtractionError, match="File not found"):
            extract_contract_boundary("nonexistent.yaml")
    
    def test_unsupported_file_type(self, tmp_path):
        """Test error for unsupported file type."""
        txt_file = tmp_path / "test.txt"
        txt_file.write_text("some content")
        
        with pytest.raises(ContractExtractionError, match="Unsupported file type"):
            extract_contract_boundary(str(txt_file))
    
    def test_invalid_yaml(self, tmp_path):
        """Test error for invalid YAML."""
        yaml_file = tmp_path / "invalid.yaml"
        yaml_file.write_text("invalid: yaml: content:")
        
        with pytest.raises(ContractExtractionError, match="Failed to parse YAML"):
            extract_contract_boundary(str(yaml_file))
    
    def test_invalid_python(self, tmp_path):
        """Test error for invalid Python syntax."""
        python_file = tmp_path / "invalid.py"
        python_file.write_text("def invalid syntax")
        
        with pytest.raises(ContractExtractionError, match="Failed to parse Python"):
            extract_contract_boundary(str(python_file))
