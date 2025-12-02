"""
Markdown Contract Extractor - Extracts contract boundaries from Markdown runbooks.
"""

import re
from typing import List, Dict
from contract_extractor import (
    ContractBoundary,
    Parameter,
    FileType,
    ContractExtractionError
)


class MarkdownContractExtractor:
    """Extracts contract boundaries from Markdown runbook files."""
    
    def extract(self, file_path: str) -> ContractBoundary:
        """
        Extract contract boundary from Markdown runbook.
        
        Extracts:
        - ## Symptoms section
        - ## Diagnosis section
        - ## Resolution section
        
        Ignores:
        - Anecdotes and background information
        
        Args:
            file_path: Path to Markdown file
            
        Returns:
            ContractBoundary with extracted sections as parameters
            
        Raises:
            ContractExtractionError: If extraction fails
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            raise ContractExtractionError(f"Failed to read Markdown file: {e}")
        
        parameters = []
        metadata = {}
        
        # Extract title (first # heading)
        title_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
        if title_match:
            metadata['title'] = title_match.group(1).strip()
        
        # Extract sections
        sections = self._extract_sections(content)
        
        # Create parameters for each section
        for section_name, section_content in sections.items():
            param = Parameter(
                name=section_name,
                type="section",
                required=False,
                description=section_content[:200] if section_content else None
            )
            parameters.append(param)
        
        metadata['sections'] = list(sections.keys())
        
        return ContractBoundary(
            file_path=file_path,
            file_type=FileType.MARKDOWN,
            parameters=parameters,
            metadata=metadata
        )
    
    def _extract_sections(self, content: str) -> Dict[str, str]:
        """
        Extract ## level sections from markdown.
        
        Returns:
            Dictionary mapping section names to content
        """
        sections = {}
        
        # Pattern to match ## headings
        section_pattern = r'^##\s+(.+?)$'
        
        # Split content by ## headings
        parts = re.split(section_pattern, content, flags=re.MULTILINE)
        
        # parts[0] is content before first ##
        # parts[1] is first section name, parts[2] is its content
        # parts[3] is second section name, parts[4] is its content, etc.
        
        for i in range(1, len(parts), 2):
            if i + 1 < len(parts):
                section_name = parts[i].strip()
                section_content = parts[i + 1].strip()
                sections[section_name] = section_content
        
        return sections
