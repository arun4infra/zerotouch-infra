"""
Contract Boundary Extractor - Extracts API contracts from various file types.

This module provides functionality to extract contract boundaries (parameters,
schemas, signatures) from different file types without including implementation details.
"""

from enum import Enum
from dataclasses import dataclass
from typing import List, Optional, Any
from pathlib import Path


class FileType(Enum):
    """Supported file types for contract extraction."""
    YAML = "yaml"
    PYTHON = "python"
    REGO = "rego"
    MARKDOWN = "markdown"
    UNKNOWN = "unknown"


@dataclass
class Parameter:
    """Represents a parameter in a contract boundary."""
    name: str
    type: Optional[str] = None
    required: bool = False
    default: Optional[Any] = None
    description: Optional[str] = None


@dataclass
class ContractBoundary:
    """Represents the contract boundary extracted from a file."""
    file_path: str
    file_type: FileType
    parameters: List[Parameter]
    metadata: dict


class ContractExtractionError(Exception):
    """Contract extraction failed."""
    pass


def extract_contract_boundary(file_path: str) -> ContractBoundary:
    """
    Extract contract boundary from a file.
    
    Args:
        file_path: Path to file to extract contract from
        
    Returns:
        ContractBoundary with extracted parameters and metadata
        
    Raises:
        ContractExtractionError: If extraction fails
        
    Example:
        boundary = extract_contract_boundary("composition.yaml")
        for param in boundary.parameters:
            print(f"{param.name}: {param.type}")
    """
    path = Path(file_path)
    
    if not path.exists():
        raise ContractExtractionError(f"File not found: {file_path}")
    
    # Determine file type
    file_type = _detect_file_type(path)
    
    if file_type == FileType.UNKNOWN:
        raise ContractExtractionError(f"Unsupported file type: {file_path}")
    
    # Extract based on file type
    if file_type == FileType.YAML:
        from yaml_extractor import YAMLContractExtractor
        extractor = YAMLContractExtractor()
    elif file_type == FileType.PYTHON:
        from python_extractor import PythonContractExtractor
        extractor = PythonContractExtractor()
    elif file_type == FileType.REGO:
        from rego_extractor import RegoContractExtractor
        extractor = RegoContractExtractor()
    elif file_type == FileType.MARKDOWN:
        from markdown_extractor import MarkdownContractExtractor
        extractor = MarkdownContractExtractor()
    
    return extractor.extract(file_path)


def _detect_file_type(path: Path) -> FileType:
    """Detect file type from extension."""
    suffix = path.suffix.lower()
    
    if suffix in ['.yaml', '.yml']:
        return FileType.YAML
    elif suffix == '.py':
        return FileType.PYTHON
    elif suffix == '.rego':
        return FileType.REGO
    elif suffix in ['.md', '.markdown']:
        return FileType.MARKDOWN
    else:
        return FileType.UNKNOWN
