"""
Unit tests for mdx_validator module.
"""

import pytest
from pathlib import Path

from mdx_validator import (
    validate_mdx,
    ValidationResult,
    MDXValidationError
)


class TestParamFieldValidation:
    """Tests for ParamField component validation."""
    
    def test_param_field_missing_path(self, tmp_path):
        """Test ParamField validation with missing path attribute."""
        mdx_content = """---
title: Test
category: spec
description: Test spec
---

<ParamField type="string">
  Test parameter
</ParamField>
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("ParamField requires 'path' attribute" in e.message for e in result.errors)
    
    def test_param_field_missing_type(self, tmp_path):
        """Test ParamField validation with missing type attribute."""
        mdx_content = """---
title: Test
category: spec
description: Test spec
---

<ParamField path="config.host">
  Test parameter
</ParamField>
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("ParamField requires 'type' attribute" in e.message for e in result.errors)
    
    def test_param_field_valid(self, tmp_path):
        """Test valid ParamField component."""
        mdx_content = """---
title: Test
category: spec
description: Test spec
---

<ParamField path="config.host" type="string">
  Test parameter
</ParamField>
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert result.valid


class TestStepValidation:
    """Tests for Step component validation."""
    
    def test_step_missing_title(self, tmp_path):
        """Test Step validation with missing title attribute."""
        mdx_content = """---
title: Test
category: runbook
description: Test runbook
---

<Steps>
  <Step>
    Do something
  </Step>
</Steps>
"""
        mdx_file = tmp_path / "test-runbook.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Step requires 'title' attribute" in e.message for e in result.errors)
    
    def test_step_valid(self, tmp_path):
        """Test valid Step component."""
        mdx_content = """---
title: Test
category: runbook
description: Test runbook
---

<Steps>
  <Step title="First step">
    Do something
  </Step>
</Steps>
"""
        mdx_file = tmp_path / "test-runbook.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert result.valid


class TestUnclosedTags:
    """Tests for unclosed tag detection."""
    
    def test_unclosed_param_field(self, tmp_path):
        """Test detection of unclosed ParamField tag."""
        mdx_content = """---
title: Test
category: spec
description: Test spec
---

<ParamField path="config.host" type="string">
  Test parameter
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Unclosed tag: <ParamField>" in e.message for e in result.errors)
    
    def test_unclosed_steps(self, tmp_path):
        """Test detection of unclosed Steps tag."""
        mdx_content = """---
title: Test
category: runbook
description: Test runbook
---

<Steps>
  <Step title="First">
    Content
  </Step>
"""
        mdx_file = tmp_path / "test-runbook.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Unclosed tag: <Steps>" in e.message for e in result.errors)
    
    def test_self_closing_tags_valid(self, tmp_path):
        """Test that self-closing tags are valid."""
        mdx_content = """---
title: Test
category: spec
description: Test spec
---

<ParamField path="config.host" type="string" />
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert result.valid


class TestFrontmatterValidation:
    """Tests for frontmatter validation."""
    
    def test_missing_frontmatter(self, tmp_path):
        """Test validation with missing frontmatter."""
        mdx_content = """# Test Document

Some content here.
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Missing frontmatter section" in e.message for e in result.errors)
    
    def test_missing_required_fields(self, tmp_path):
        """Test validation with missing required frontmatter fields."""
        mdx_content = """---
title: Test
---

Content here.
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Missing required frontmatter field: category" in e.message for e in result.errors)
        assert any("Missing required frontmatter field: description" in e.message for e in result.errors)
    
    def test_invalid_category(self, tmp_path):
        """Test validation with invalid category value."""
        mdx_content = """---
title: Test
category: invalid
description: Test description
---

Content here.
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Invalid category 'invalid'" in e.message for e in result.errors)
    
    def test_valid_frontmatter(self, tmp_path):
        """Test validation with valid frontmatter."""
        mdx_content = """---
title: Test Spec
category: spec
description: A test specification
tags: [test, example]
---

Content here.
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert result.valid


class TestFilenameValidation:
    """Tests for filename validation."""
    
    def test_invalid_extension(self, tmp_path):
        """Test validation with wrong file extension."""
        md_file = tmp_path / "test-spec.md"
        md_file.write_text("""---
title: Test
category: spec
description: Test
---
""")
        
        result = validate_mdx(str(md_file))
        
        assert not result.valid
        assert any("must have .mdx extension" in e.message for e in result.errors)
    
    def test_non_kebab_case(self, tmp_path):
        """Test validation with non-kebab-case filename."""
        mdx_file = tmp_path / "TestSpec.mdx"
        mdx_file.write_text("""---
title: Test
category: spec
description: Test
---
""")
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("must be kebab-case" in e.message for e in result.errors)
    
    def test_too_many_words(self, tmp_path):
        """Test validation with too many words in filename."""
        mdx_file = tmp_path / "this-is-a-very-long-filename.mdx"
        mdx_file.write_text("""---
title: Test
category: spec
description: Test
---
""")
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("must have max 3 words" in e.message for e in result.errors)
    
    def test_filename_with_timestamp(self, tmp_path):
        """Test validation with timestamp in filename."""
        mdx_file = tmp_path / "spec-2024-01-15.mdx"
        mdx_file.write_text("""---
title: Test
category: spec
description: Test
---
""")
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("must not contain timestamps" in e.message for e in result.errors)
    
    def test_valid_filename(self, tmp_path):
        """Test validation with valid filename."""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text("""---
title: Test
category: spec
description: Test
---
""")
        
        result = validate_mdx(str(mdx_file))
        
        assert result.valid


class TestUnknownComponents:
    """Tests for unknown component detection."""
    
    def test_unknown_component(self, tmp_path):
        """Test detection of unknown/unapproved component."""
        mdx_content = """---
title: Test
category: spec
description: Test
---

<CustomComponent>
  Some content
</CustomComponent>
"""
        mdx_file = tmp_path / "test-spec.mdx"
        mdx_file.write_text(mdx_content)
        
        result = validate_mdx(str(mdx_file))
        
        assert not result.valid
        assert any("Unknown component: CustomComponent" in e.message for e in result.errors)


class TestFileNotFound:
    """Tests for file not found error."""
    
    def test_file_not_found(self):
        """Test validation with non-existent file."""
        result = validate_mdx("nonexistent.mdx")
        
        assert not result.valid
        assert any("File not found" in e.message for e in result.errors)
