"""
YAML Contract Extractor - Extracts contract boundaries from Crossplane YAML files.
"""

import yaml
from pathlib import Path
from typing import List, Dict, Any
from contract_extractor import (
    ContractBoundary,
    Parameter,
    FileType,
    ContractExtractionError
)


class YAMLContractExtractor:
    """Extracts contract boundaries from Crossplane YAML files."""
    
    def extract(self, file_path: str) -> ContractBoundary:
        """
        Extract contract boundary from Crossplane YAML file.
        
        Extracts:
        - spec.forProvider.* parameters
        - spec.compositeTypeRef schemas
        - metadata.* fields
        
        Ignores:
        - status.* fields
        - patches.* fields
        
        Args:
            file_path: Path to YAML file
            
        Returns:
            ContractBoundary with extracted parameters
            
        Raises:
            ContractExtractionError: If extraction fails
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
        except Exception as e:
            raise ContractExtractionError(f"Failed to parse YAML: {e}")
        
        if not isinstance(data, dict):
            raise ContractExtractionError("YAML file must contain a dictionary")
        
        parameters = []
        metadata = {}
        
        # Extract metadata
        if 'metadata' in data:
            metadata = self._extract_metadata(data['metadata'])
        
        # Extract spec.forProvider parameters
        if 'spec' in data and isinstance(data['spec'], dict):
            if 'forProvider' in data['spec']:
                params = self._extract_for_provider(data['spec']['forProvider'])
                parameters.extend(params)
            
            # Extract compositeTypeRef
            if 'compositeTypeRef' in data['spec']:
                metadata['compositeTypeRef'] = data['spec']['compositeTypeRef']
        
        return ContractBoundary(
            file_path=file_path,
            file_type=FileType.YAML,
            parameters=parameters,
            metadata=metadata
        )
    
    def _extract_metadata(self, metadata_dict: Dict[str, Any]) -> Dict[str, Any]:
        """Extract relevant metadata fields."""
        result = {}
        
        # Extract common metadata fields
        for key in ['name', 'namespace', 'labels', 'annotations']:
            if key in metadata_dict:
                result[key] = metadata_dict[key]
        
        return result
    
    def _extract_for_provider(self, for_provider: Dict[str, Any], prefix: str = "") -> List[Parameter]:
        """
        Recursively extract parameters from forProvider section.
        
        Args:
            for_provider: forProvider dictionary
            prefix: Prefix for nested parameters
            
        Returns:
            List of Parameter objects
        """
        parameters = []
        
        for key, value in for_provider.items():
            param_name = f"{prefix}{key}" if prefix else key
            
            # Determine parameter type and extract info
            param_type = self._infer_type(value)
            
            param = Parameter(
                name=param_name,
                type=param_type,
                required=False,  # Would need schema to determine
                default=value if not isinstance(value, (dict, list)) else None
            )
            
            parameters.append(param)
            
            # Recursively extract nested parameters
            if isinstance(value, dict):
                nested_params = self._extract_for_provider(value, f"{param_name}.")
                parameters.extend(nested_params)
        
        return parameters
    
    def _infer_type(self, value: Any) -> str:
        """Infer parameter type from value."""
        if isinstance(value, bool):
            return "boolean"
        elif isinstance(value, int):
            return "integer"
        elif isinstance(value, float):
            return "number"
        elif isinstance(value, str):
            return "string"
        elif isinstance(value, list):
            return "array"
        elif isinstance(value, dict):
            return "object"
        else:
            return "unknown"
