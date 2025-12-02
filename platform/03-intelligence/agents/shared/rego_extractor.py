"""
Rego Contract Extractor - Extracts contract boundaries from Rego policy files.
"""

import re
from typing import List
from contract_extractor import (
    ContractBoundary,
    Parameter,
    FileType,
    ContractExtractionError
)


class RegoContractExtractor:
    """Extracts contract boundaries from Rego files using regex."""
    
    def extract(self, file_path: str) -> ContractBoundary:
        """
        Extract contract boundary from Rego file.
        
        Extracts:
        - Rule names
        - Input/output schemas
        
        Ignores:
        - Rule logic/implementation
        
        Args:
            file_path: Path to Rego file
            
        Returns:
            ContractBoundary with extracted parameters
            
        Raises:
            ContractExtractionError: If extraction fails
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            raise ContractExtractionError(f"Failed to read Rego file: {e}")
        
        parameters = []
        metadata = {}
        
        # Extract package name
        package_match = re.search(r'package\s+([\w.]+)', content)
        if package_match:
            metadata['package'] = package_match.group(1)
        
        # Extract rule definitions
        # Pattern: rule_name[params] { ... } or rule_name := value { ... }
        rule_pattern = r'(\w+)(?:\[([^\]]+)\])?\s*(?::=|=|\{)'
        
        for match in re.finditer(rule_pattern, content):
            rule_name = match.group(1)
            rule_params = match.group(2)
            
            # Skip built-in keywords
            if rule_name in ['package', 'import', 'default']:
                continue
            
            param = Parameter(
                name=rule_name,
                type="rule",
                required=False
            )
            parameters.append(param)
            
            # Extract rule parameters if present
            if rule_params:
                param_names = [p.strip() for p in rule_params.split(',')]
                for param_name in param_names:
                    param = Parameter(
                        name=f"{rule_name}.{param_name}",
                        type="input",
                        required=True
                    )
                    parameters.append(param)
        
        # Extract input references
        input_pattern = r'input\.(\w+(?:\.\w+)*)'
        input_refs = set(re.findall(input_pattern, content))
        
        for input_ref in input_refs:
            param = Parameter(
                name=f"input.{input_ref}",
                type="input",
                required=False
            )
            parameters.append(param)
        
        metadata['rules'] = [p.name for p in parameters if p.type == "rule"]
        
        return ContractBoundary(
            file_path=file_path,
            file_type=FileType.REGO,
            parameters=parameters,
            metadata=metadata
        )
