"""
Python Contract Extractor - Extracts contract boundaries from Python files.
"""

import ast
from typing import List
from contract_extractor import (
    ContractBoundary,
    Parameter,
    FileType,
    ContractExtractionError
)


class PythonContractExtractor:
    """Extracts contract boundaries from Python files using AST parsing."""
    
    def extract(self, file_path: str) -> ContractBoundary:
        """
        Extract contract boundary from Python file.
        
        Extracts:
        - Function signatures (def, async def)
        - Class definitions (dataclass, Pydantic models)
        - Type hints
        
        Ignores:
        - Function bodies
        - Private methods (starting with _)
        
        Args:
            file_path: Path to Python file
            
        Returns:
            ContractBoundary with extracted parameters
            
        Raises:
            ContractExtractionError: If extraction fails
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                source = f.read()
            tree = ast.parse(source)
        except Exception as e:
            raise ContractExtractionError(f"Failed to parse Python file: {e}")
        
        parameters = []
        metadata = {}
        
        # Extract functions and classes
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) or isinstance(node, ast.AsyncFunctionDef):
                # Skip private methods
                if not node.name.startswith('_'):
                    params = self._extract_function_params(node)
                    parameters.extend(params)
            
            elif isinstance(node, ast.ClassDef):
                # Extract class info
                class_params = self._extract_class_params(node)
                parameters.extend(class_params)
                
                # Store class metadata
                if 'classes' not in metadata:
                    metadata['classes'] = []
                metadata['classes'].append(node.name)
        
        return ContractBoundary(
            file_path=file_path,
            file_type=FileType.PYTHON,
            parameters=parameters,
            metadata=metadata
        )
    
    def _extract_function_params(self, node: ast.FunctionDef) -> List[Parameter]:
        """Extract parameters from function definition."""
        parameters = []
        
        for arg in node.args.args:
            # Skip self and cls
            if arg.arg in ['self', 'cls']:
                continue
            
            param_type = None
            if arg.annotation:
                param_type = ast.unparse(arg.annotation)
            
            param = Parameter(
                name=f"{node.name}.{arg.arg}",
                type=param_type,
                required=True
            )
            parameters.append(param)
        
        # Extract return type
        if node.returns:
            return_param = Parameter(
                name=f"{node.name}.return",
                type=ast.unparse(node.returns),
                required=False
            )
            parameters.append(return_param)
        
        return parameters
    
    def _extract_class_params(self, node: ast.ClassDef) -> List[Parameter]:
        """Extract parameters from class definition."""
        parameters = []
        
        # Check if it's a dataclass or Pydantic model
        is_dataclass = any(
            isinstance(dec, ast.Name) and dec.id == 'dataclass'
            for dec in node.decorator_list
        )
        
        # Extract class attributes
        for item in node.body:
            if isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
                attr_name = item.target.id
                attr_type = ast.unparse(item.annotation) if item.annotation else None
                
                param = Parameter(
                    name=f"{node.name}.{attr_name}",
                    type=attr_type,
                    required=True
                )
                parameters.append(param)
        
        return parameters
