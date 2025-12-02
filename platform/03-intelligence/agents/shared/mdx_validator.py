"""
MDX Validator - Validates MDX documentation files for compliance.

This module validates MDX files for proper component usage, frontmatter,
and filename conventions.
"""

from enum import Enum
from dataclasses import dataclass
from typing import List, Optional
from pathlib import Path
import re


class ComponentType(Enum):
    """Approved MDX component types."""
    PARAM_FIELD = "ParamField"
    STEP = "Step"
    STEPS = "Steps"
    CODE_BLOCK = "CodeBlock"
    CALLOUT = "Callout"


@dataclass
class ValidationError:
    """Represents a validation error."""
    line: Optional[int]
    message: str
    severity: str = "error"


@dataclass
class ValidationResult:
    """Result of MDX validation."""
    valid: bool
    errors: List[ValidationError]
    warnings: List[ValidationError]


class MDXValidationError(Exception):
    """MDX validation failed."""
    pass


def validate_mdx(file_path: str) -> ValidationResult:
    """
    Validate MDX file for compliance.
    
    Validates:
    - Component usage (ParamField, Step, Steps)
    - Frontmatter (title, category, description)
    - Filename (kebab-case, max 3 words, no timestamps)
    
    Args:
        file_path: Path to MDX file
        
    Returns:
        ValidationResult with errors and warnings
        
    Example:
        result = validate_mdx("spec.mdx")
        if not result.valid:
            for error in result.errors:
                print(f"Line {error.line}: {error.message}")
    """
    path = Path(file_path)
    
    if not path.exists():
        return ValidationResult(
            valid=False,
            errors=[ValidationError(None, f"File not found: {file_path}")],
            warnings=[]
        )
    
    errors = []
    warnings = []
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return ValidationResult(
            valid=False,
            errors=[ValidationError(None, f"Failed to read file: {e}")],
            warnings=[]
        )
    
    # Validate filename
    filename_errors = _validate_filename(path)
    errors.extend(filename_errors)
    
    # Validate frontmatter
    frontmatter_errors = _validate_frontmatter(content)
    errors.extend(frontmatter_errors)
    
    # Validate components
    component_errors = _validate_components(content)
    errors.extend(component_errors)
    
    return ValidationResult(
        valid=len(errors) == 0,
        errors=errors,
        warnings=warnings
    )


def _validate_filename(path: Path) -> List[ValidationError]:
    """Validate filename conventions."""
    errors = []
    
    filename = path.stem
    
    # Check extension
    if path.suffix != '.mdx':
        errors.append(ValidationError(
            None,
            f"File must have .mdx extension, got: {path.suffix}"
        ))
    
    # Check kebab-case
    if not re.match(r'^[a-z0-9]+(-[a-z0-9]+)*$', filename):
        errors.append(ValidationError(
            None,
            f"Filename must be kebab-case: {filename}"
        ))
    
    # Check max 3 words
    words = filename.split('-')
    if len(words) > 3:
        errors.append(ValidationError(
            None,
            f"Filename must have max 3 words, got {len(words)}: {filename}"
        ))
    
    # Check no timestamps
    if re.search(r'\d{4}-\d{2}-\d{2}|\d{8}|\d{10}', filename):
        errors.append(ValidationError(
            None,
            f"Filename must not contain timestamps: {filename}"
        ))
    
    return errors


def _validate_frontmatter(content: str) -> List[ValidationError]:
    """Validate frontmatter section."""
    errors = []
    
    # Extract frontmatter
    frontmatter_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    
    if not frontmatter_match:
        errors.append(ValidationError(
            1,
            "Missing frontmatter section (must start with ---)"
        ))
        return errors
    
    frontmatter = frontmatter_match.group(1)
    
    # Check required fields
    required_fields = ['title', 'category', 'description']
    for field in required_fields:
        if not re.search(rf'^{field}:', frontmatter, re.MULTILINE):
            errors.append(ValidationError(
                None,
                f"Missing required frontmatter field: {field}"
            ))
    
    # Validate category value
    category_match = re.search(r'^category:\s*(.+)$', frontmatter, re.MULTILINE)
    if category_match:
        category = category_match.group(1).strip()
        valid_categories = ['spec', 'runbook', 'adr']
        if category not in valid_categories:
            errors.append(ValidationError(
                None,
                f"Invalid category '{category}', must be one of: {', '.join(valid_categories)}"
            ))
    
    return errors


def _validate_components(content: str) -> List[ValidationError]:
    """Validate MDX components."""
    errors = []
    
    # Find all component tags
    component_pattern = r'<(\w+)([^>]*)/?>'
    
    for match in re.finditer(component_pattern, content):
        component_name = match.group(1)
        attributes = match.group(2)
        line_num = content[:match.start()].count('\n') + 1
        
        # Check if component is whitelisted
        valid_components = [c.value for c in ComponentType]
        if component_name not in valid_components:
            errors.append(ValidationError(
                line_num,
                f"Unknown component: {component_name}. Allowed: {', '.join(valid_components)}"
            ))
            continue
        
        # Validate component-specific requirements
        if component_name == "ParamField":
            if 'path=' not in attributes and 'path =' not in attributes:
                errors.append(ValidationError(
                    line_num,
                    "ParamField requires 'path' attribute"
                ))
            if 'type=' not in attributes and 'type =' not in attributes:
                errors.append(ValidationError(
                    line_num,
                    "ParamField requires 'type' attribute"
                ))
        
        elif component_name == "Step":
            if 'title=' not in attributes and 'title =' not in attributes:
                errors.append(ValidationError(
                    line_num,
                    "Step requires 'title' attribute"
                ))
    
    # Check for unclosed tags
    unclosed_errors = _check_unclosed_tags(content)
    errors.extend(unclosed_errors)
    
    return errors


def _check_unclosed_tags(content: str) -> List[ValidationError]:
    """Check for unclosed component tags."""
    errors = []
    
    # Track open tags
    tag_stack = []
    
    # Find all opening and closing tags
    tag_pattern = r'<(/?)(\w+)([^>]*)/?>'
    
    for match in re.finditer(tag_pattern, content):
        is_closing = match.group(1) == '/'
        tag_name = match.group(2)
        is_self_closing = match.group(3).endswith('/')
        line_num = content[:match.start()].count('\n') + 1
        
        if is_closing:
            if not tag_stack or tag_stack[-1][0] != tag_name:
                errors.append(ValidationError(
                    line_num,
                    f"Closing tag </{tag_name}> without matching opening tag"
                ))
            else:
                tag_stack.pop()
        elif not is_self_closing:
            tag_stack.append((tag_name, line_num))
    
    # Report unclosed tags
    for tag_name, line_num in tag_stack:
        errors.append(ValidationError(
            line_num,
            f"Unclosed tag: <{tag_name}>"
        ))
    
    return errors
