# Twin Docs MDX Improvements Proposal

**Date:** 2025-12-01  
**Status:** Pending Review  
**Author:** Kiro AI Assistant  
**Reviewer:** Platform Team

---

## Executive Summary

This document proposes upgrading the Twin Docs workflow from Markdown (`.md`) to MDX (`.mdx`) with structured components, based on analysis of Mintlify's documentation patterns. The goal is to create **structured, machine-readable documentation** that serves both human readers and AI agents while maintaining the platform-first philosophy.

**Key Principle:** Use Mintlify's MDX standard for structure, but keep Qdrant as the retrieval engine. Deploy to Mintlify (or similar) only for human viewing.

---

## Context: Platform vs Web App Documentation

### Critical Distinction

| Aspect | Web App Docs (Mintlify) | Platform Docs (Twin Docs) |
|:-------|:------------------------|:--------------------------|
| **Audience** | External developers, customers | Internal platform engineers |
| **Purpose** | Product marketing + API reference | Infrastructure specifications + runbooks |
| **Update Frequency** | Manual, curated | Automated, PR-triggered |
| **Retrieval** | Human search, AI chat | Agent queries (<50ms), human reference |
| **Privacy** | Public or customer-facing | Internal, security-sensitive |
| **Complexity** | Multi-language, versioning, branding | Single language, API versions, minimal styling |

### What We Should Adopt from Mintlify

✅ **MDX component structure** - Makes docs machine-readable  
✅ **Navigation manifest** (`docs.json`) - Prevents orphaned files  
✅ **Semantic chunking** - Improves vector search quality  
✅ **`<Steps>` for runbooks** - Visual troubleshooting paths  
✅ **`<ParamField>` for specs** - Structured parameter documentation  
✅ **`<CodeGroup>` for examples** - Show Intent vs Reality side-by-side  

### What We Should NOT Adopt from Mintlify

❌ **Multi-language i18n** - Platform teams use English only  
❌ **Custom themes/branding** - Focus on content, not aesthetics  
❌ **Social media integration** - Internal platform, no external sharing  
❌ **Custom domains** - Internal deployment only  
❌ **Complex navigation** (tabs, dropdowns, products) - Keep it simple  

---

## Proposed Improvements

### 1. Migrate from Markdown to MDX

**Current State:**
```markdown
## Configuration Parameters

| Parameter | Type | Required | Default | Validation | Description |
|:----------|:-----|:---------|:--------|:-----------|:------------|
| `spec.parameters.replicas` | integer | No | `1` | 1-10 | Number of pod replicas |
| `spec.parameters.storageSize` | string | No | `10Gi` | Valid k8s quantity | PVC storage size |
```

**Proposed State:**
```mdx
## Configuration Parameters

<ParamField path="spec.parameters.replicas" type="integer" default="1" required={false}>
  Number of pod replicas for the service.
  
  **Validation:** Must be between 1 and 10
  
  **Example:**
  ```yaml
  replicas: 3
  ```
</ParamField>

<ParamField path="spec.parameters.storageSize" type="string" default="10Gi" required={false}>
  PVC storage size for persistent data.
  
  **Validation:** Must be a valid Kubernetes quantity (e.g., 10Gi, 50Gi)
  
  **Example:**
  ```yaml
  storageSize: 50Gi
  ```
</ParamField>
```

**Justification:**

1. **Machine-Readable Structure**
   - Markdown tables are brittle (formatting breaks easily)
   - MDX components have explicit attributes (`path`, `type`, `default`)
   - Agents can parse XML-like tags deterministically

2. **Better Vector Chunking**
   - Each `<ParamField>` becomes a semantic chunk
   - Qdrant can index by parameter path
   - Query "What is the replicas parameter?" returns exact chunk

3. **Richer Documentation**
   - Nested properties (e.g., `spec.parameters.database.host`)
   - Inline examples and validation rules
   - Type highlighting and required indicators

4. **Human Readability**
   - Interactive components when rendered
   - Collapsible nested fields
   - Syntax highlighting in examples

**Implementation Impact:**
- Update `artifacts/templates/spec-template.md` → `spec-template.mdx`
- Update agent prompt to generate `<ParamField>` instead of tables
- Add MDX validation to `upsert_twin_doc` tool

---

### 2. Add Navigation Manifest (`docs.json`)

**Current State:**
- Files created in `artifacts/specs/` and `artifacts/runbooks/`
- No explicit navigation structure
- Risk of orphaned files

**Proposed State:**
```json
{
  "$schema": "./docs-schema.json",
  "name": "Platform Documentation",
  "version": "1.0",
  "navigation": {
    "groups": [
      {
        "group": "Infrastructure",
        "icon": "server",
        "pages": [
          "specs/postgres",
          "specs/redis",
          "specs/dragonfly"
        ]
      },
      {
        "group": "APIs",
        "icon": "code",
        "pages": [
          "specs/webservice",
          "specs/graphql-api"
        ]
      },
      {
        "group": "Runbooks",
        "icon": "book-open",
        "pages": [
          "runbooks/postgres-disk-issue",
          "runbooks/redis-memory-spike"
        ]
      }
    ]
  }
}
```

**Justification:**

1. **Discoverability**
   - All documentation is explicitly listed
   - No orphaned files that humans can't find
   - Clear categorization (Infrastructure, APIs, Runbooks)

2. **Agent Navigation**
   - Agent can read `docs.json` to understand structure
   - Can suggest where to add new documentation
   - Can validate that all compositions have Twin Docs

3. **Deployment Ready**
   - `artifacts/` folder can be deployed to Mintlify/Vercel as-is
   - Humans get a beautiful, navigable documentation site
   - No manual navigation setup required

4. **Simplicity**
   - Only use `groups` and `pages` (no tabs, dropdowns, etc.)
   - Platform-appropriate complexity level
   - Easy for agent to maintain

**Implementation Impact:**
- Create `artifacts/docs.json` with initial structure
- Update `upsert_twin_doc` to accept `navigation_group` parameter
- Agent reads `docs.json`, finds appropriate group, appends new page
- Add validation: fail if file created but not added to `docs.json`
- **Concurrency Handling:** Git auto-merge typically handles JSON list appends correctly when on separate lines
- **Conflict Detection:** If merge conflict detected on `docs.json`, Agent must rebase and retry
- **Atomic Guarantee:** Both file creation and `docs.json` update must succeed or both fail

---

### 3. Enhance Runbooks with `<Steps>` Component

**Current State:**
```markdown
## Diagnosis Steps

1. Check disk usage: `df -h`
2. Identify large tables: `SELECT pg_size_pretty(...)`
3. Check WAL files: `ls -lh /var/lib/postgresql/data/pg_wal/`
```

**Proposed State:**
```mdx
## Diagnosis

<Steps>
  <Step title="Check disk usage">
    ```bash
    df -h
    kubectl get pvc -n postgres
    ```
    
    Look for volumes at >90% capacity.
  </Step>
  
  <Step title="Identify large tables">
    ```sql
    SELECT 
      schemaname,
      tablename,
      pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
    FROM pg_tables
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
    LIMIT 10;
    ```
    
    Focus on tables larger than 10GB.
  </Step>
  
  <Step title="Check WAL files">
    ```bash
    kubectl exec -it postgres-0 -n postgres -- ls -lh /var/lib/postgresql/data/pg_wal/
    ```
    
    WAL files should be archived regularly. If you see 100+ files, archiving is failing.
  </Step>
</Steps>
```

**Justification:**

1. **Visual Troubleshooting Path**
   - Numbered steps with clear titles
   - Progress indicator when rendered
   - Easier to follow during incidents

2. **Structured for Agents**
   - Each `<Step>` is a semantic unit
   - Agent can extract "Step 2: Identify large tables" precisely
   - Better than parsing numbered lists

3. **Richer Context**
   - Each step can have multiple code blocks
   - Inline explanations and warnings
   - Expected outputs and thresholds

4. **Chunking Benefits**
   - Each step becomes a separate vector chunk
   - Query "How to check disk usage?" returns exact step
   - More precise retrieval than full runbook

**Implementation Impact:**
- Update `artifacts/templates/runbook-template.md` → `runbook-template.mdx`
- Update agent prompt to generate `<Steps>` for diagnosis/resolution
- Add `<Warning>` and `<Tip>` components for important notes

---

### 4. Add `<CodeGroup>` for Intent vs Reality

**Current State:**
- Spec URL in PR description
- Code in composition file
- No visual comparison in documentation

**Proposed State:**
```mdx
## Configuration Example

<CodeGroup>
```yaml Spec (Intent)
# From GitHub Issue #123
spec:
  parameters:
    replicas: 3  # Max 3 replicas for cost control
    storage: 10Gi
```

```yaml Code (Reality)
# From platform/03-intelligence/postgres.yaml
spec:
  parameters:
    replicas: 3
    storage: 10Gi
```
</CodeGroup>

<Note>
  ✅ Code aligns with spec requirements
</Note>
```

**Justification:**

1. **Gatekeeper Transparency**
   - Shows what the spec required
   - Shows what the code implements
   - Makes alignment (or misalignment) obvious

2. **Audit Trail**
   - Humans can see the business intent
   - Humans can see the technical implementation
   - Reduces "why was this built this way?" questions

3. **Educational Value**
   - New engineers learn the "why" behind configurations
   - Shows the relationship between requirements and code
   - Documents decision-making process

4. **Agent Validation**
   - Agent can generate this comparison automatically
   - Makes Gatekeeper logic transparent
   - Easier to debug false positives

**Implementation Impact:**
- Agent generates `<CodeGroup>` when creating Twin Doc
- Fetches spec from GitHub issue
- Extracts relevant code from composition
- Shows side-by-side comparison

---

### 5. Implement MDX-Aware Qdrant Chunking

**Current State:**
```python
def chunk_document(content):
    """Chunk by 512 tokens with 50% overlap"""
    chunks = []
    for i in range(0, len(content), 256):
        chunk = content[i:i+512]
        chunks.append(chunk)
    return chunks
```

**Proposed State:**
```python
def chunk_mdx_document(mdx_content):
    """
    Chunk MDX by semantic components instead of arbitrary character counts
    """
    chunks = []
    
    # Extract frontmatter as one chunk
    frontmatter = extract_frontmatter(mdx_content)
    chunks.append({
        "type": "metadata",
        "content": frontmatter,
        "tokens": count_tokens(frontmatter)
    })
    
    # Extract each <ParamField> as a separate chunk
    param_fields = extract_components(mdx_content, "ParamField")
    for field in param_fields:
        chunks.append({
            "type": "parameter",
            "path": field.get("path"),
            "content": field.content,
            "tokens": count_tokens(field.content)
        })
    
    # Extract each <Step> as a separate chunk
    steps = extract_components(mdx_content, "Step")
    for i, step in enumerate(steps):
        chunks.append({
            "type": "step",
            "index": i + 1,
            "title": step.get("title"),
            "content": step.content,
            "tokens": count_tokens(step.content)
        })
    
    # Extract regular sections (## headings)
    sections = extract_sections(mdx_content)
    for section in sections:
        if section.tokens > 512:
            # Split large sections
            subsections = split_by_tokens(section.content, 512, overlap=50)
            chunks.extend(subsections)
        else:
            chunks.append(section)
    
    return chunks
```

**Justification:**

1. **Semantic Boundaries**
   - Don't split in the middle of a `<ParamField>`
   - Each component is a complete semantic unit
   - Preserves context and meaning

2. **Precise Retrieval**
   - Query "replicas parameter" returns exact `<ParamField>`
   - Query "check disk usage" returns exact `<Step>`
   - No partial or fragmented results

3. **Metadata Enrichment**
   - Store component type in Qdrant payload
   - Store parameter path or step index
   - Enable filtered searches (e.g., "only parameters")

4. **Better Agent Reasoning**
   - Agent gets complete, structured information
   - No need to reconstruct context from fragments
   - Reduces hallucination risk

**Implementation Impact:**
- Update `sync_to_qdrant` MCP tool
- Add MDX parsing library (e.g., `mdx-js/mdx`)
- Update Qdrant payload schema to include component metadata
- Test with existing Twin Docs

---

### 6. Add MDX Validation to `upsert_twin_doc`

**Current State:**
```python
def upsert_twin_doc(file_path, markdown_content, pr_number, commit_message):
    # Validate frontmatter
    validate_doc_schemas(markdown_content)
    # Validate prose
    detect_prose(markdown_content)
    # Validate filename
    validate_filenames(file_path)
    # If valid, commit
    commit_to_pr(file_path, markdown_content, pr_number, commit_message)
```

**Proposed State:**
```python
def upsert_twin_doc(file_path, mdx_content, pr_number, commit_message, navigation_group=None):
    # Validate frontmatter
    validate_doc_schemas(mdx_content)
    
    # Validate MDX syntax
    validate_mdx_components(mdx_content)
    
    # Validate filename
    validate_filenames(file_path)
    
    # If valid, commit file
    commit_to_pr(file_path, mdx_content, pr_number, commit_message)
    
    # Update docs.json navigation
    if navigation_group:
        update_navigation_manifest(file_path, navigation_group)
        commit_to_pr("artifacts/docs.json", updated_manifest, pr_number, 
                    f"docs: add {file_path} to navigation")

def validate_mdx_components(mdx_content):
    """Validate MDX component syntax"""
    errors = []
    
    # Check for unclosed tags
    if not tags_balanced(mdx_content):
        errors.append("Unclosed MDX tags detected")
    
    # Validate <ParamField> attributes
    param_fields = extract_components(mdx_content, "ParamField")
    for field in param_fields:
        if not field.has_attribute("path"):
            errors.append(f"<ParamField> missing required 'path' attribute")
        if not field.has_attribute("type"):
            errors.append(f"<ParamField path='{field.get('path')}' missing 'type' attribute")
    
    # Validate <Step> attributes
    steps = extract_components(mdx_content, "Step")
    for step in steps:
        if not step.has_attribute("title"):
            errors.append(f"<Step> missing required 'title' attribute")
    
    # Check for invalid components
    allowed_components = ["ParamField", "Steps", "Step", "CodeGroup", "Warning", "Note", "Tip"]
    used_components = extract_all_components(mdx_content)
    for component in used_components:
        if component not in allowed_components:
            errors.append(f"Unknown component: <{component}>")
    
    if errors:
        raise ValidationError("\n".join(errors))
    
    return True
```

**Justification:**

1. **Prevent Malformed MDX**
   - LLMs can hallucinate invalid syntax
   - Catch errors before committing
   - Maintain high documentation quality

2. **Enforce Component Standards**
   - Only allow approved components
   - Require mandatory attributes
   - Prevent agent creativity that breaks rendering

3. **Atomic Operations**
   - Validate before committing (no rollback needed)
   - Update both file and `docs.json` in same PR
   - Maintain consistency

4. **Clear Error Messages**
   - Agent knows exactly what's wrong
   - Can self-correct in iteration loop
   - Reduces manual intervention

**Implementation Impact:**
- Add MDX parser to `upsert_twin_doc` tool
- Define allowed components and required attributes
- Update agent prompt with MDX syntax examples
- Test with intentionally malformed MDX

---

### 7. Enhanced Gatekeeper Diff Output

**Current State:**
```markdown
❌ Gatekeeper: Spec vs Code Mismatch

The code allows 5 replicas, but the spec limits it to 3.
```

**Proposed State:**
```markdown
## ⚠️ Gatekeeper: Spec vs Code Mismatch Detected

**File:** `platform/03-intelligence/postgres.yaml`  
**Spec:** https://github.com/org/repo/issues/123  
**Twin Doc:** [View Documentation](link)

### Mismatches Found

<CodeGroup>
```yaml Interpreted Intent
# ⚠️ AGENT INTERPRETATION of GitHub Issue #123
# Original requirement: "Limit replicas to 3 for cost control"
# This is a PROJECTION by the Librarian Agent, not a direct copy
# Source: https://github.com/org/repo/issues/123

spec:
  parameters:
    replicas: 3  # ❌ INTERPRETED MAX: 3
    storage: 10Gi
```

```yaml Code (Reality)
# From platform/03-intelligence/postgres.yaml
spec:
  parameters:
    replicas: 5  # ❌ CODE ALLOWS: Up to 5
    storage: 10Gi
```
</CodeGroup>

### Analysis

| Parameter | Spec Value | Code Value | Status |
|:----------|:-----------|:-----------|:-------|
| `replicas` | `3` (max) | `5` (max) | ❌ Mismatch |
| `storage` | `10Gi` | `10Gi` | ✅ Aligned |

### Action Required

Either:
1. **Update the code** to enforce `replicas <= 3`, OR
2. **Update the spec** (GitHub Issue #123) to allow up to 5 replicas

### Why This Matters

The spec exists to document business requirements and constraints. When code diverges from the spec, it creates:
- **Compliance risk** - Code may violate business rules
- **Documentation debt** - Twin Docs become inaccurate
- **Confusion** - Engineers don't know the "source of truth"

---
*Posted by Librarian Agent | [Gatekeeper Documentation](link)*
```

**Justification:**

1. **Actionable Feedback**
   - Clear identification of the problem
   - Specific parameter that's misaligned
   - Concrete actions to resolve

2. **Visual Comparison**
   - Side-by-side diff using `<CodeGroup>`
   - Highlights exact differences
   - Shows context (not just the mismatched line)

3. **Educational**
   - Explains why alignment matters
   - Links to relevant documentation
   - Helps engineers understand the Gatekeeper's role

4. **Audit Trail**
   - Permanent record in PR comments
   - Shows what was checked and when
   - Useful for compliance reviews

**Implementation Impact:**
- Update agent prompt with new comment template
- Generate `<CodeGroup>` comparison
- Add analysis table
- Include links to spec and Twin Doc
- **Agent must label Intent as "Interpreted Intent" with disclaimer**
- **Agent must transpile natural language requirements to YAML projection**
- **Agent must link to source GitHub issue for verification**

---

## Updated File Structure

### Before (Markdown)
```
artifacts/
├── specs/
│   ├── postgres.md
│   ├── redis.md
│   └── webservice.md
├── runbooks/
│   ├── postgres-disk-issue.md
│   └── redis-memory-spike.md
└── templates/
    ├── spec-template.md
    └── runbook-template.md
```

### After (MDX)
```
artifacts/
├── docs.json                    # ← NEW: Navigation manifest
├── specs/
│   ├── postgres.mdx             # ← Changed extension
│   ├── redis.mdx
│   └── webservice.mdx
├── runbooks/
│   ├── postgres-disk-issue.mdx  # ← Changed extension
│   └── redis-memory-spike.mdx
└── templates/
    ├── spec-template.mdx        # ← Changed extension
    └── runbook-template.mdx     # ← Changed extension
```

---

## Implementation Plan

### Phase 1: Templates and Validation (Week 1)
1. Create `spec-template.mdx` with `<ParamField>` examples
2. Create `runbook-template.mdx` with `<Steps>` examples
3. Implement `validate_mdx_components()` function
4. Add MDX validation to `upsert_twin_doc` tool
5. Test with sample MDX files
6. **Add `make docs-preview` task** (runs `mintlify dev` or equivalent for local rendering)

### Phase 2: Navigation Manifest (Week 1)
1. Create `artifacts/docs.json` with initial structure
2. Update `upsert_twin_doc` to accept `navigation_group` parameter
3. Implement `update_navigation_manifest()` function
4. Test adding new files to navigation

### Phase 3: Agent Prompt Updates (Week 2)
1. Update agent system prompt with MDX syntax examples
2. Add `<ParamField>` generation instructions
3. Add `<Steps>` generation instructions for runbooks
4. Add `<CodeGroup>` generation for Intent vs Reality
5. Test agent MDX generation

### Phase 4: Qdrant Chunking (Week 2)
1. Add MDX parsing library to `sync_to_qdrant` tool
2. Implement `chunk_mdx_document()` function
3. Update Qdrant payload schema
4. Re-index existing Twin Docs
5. Test retrieval quality

### Phase 5: Migration (Week 3)
1. Convert existing `.md` files to `.mdx`
2. Migrate Markdown tables to `<ParamField>` components
3. Migrate numbered lists to `<Steps>` components
4. Populate `docs.json` with all existing files
5. Validate all migrated files

### Phase 6: Testing and Refinement (Week 3)
1. End-to-end test: Create new composition → Twin Doc generated
2. End-to-end test: Update composition → Twin Doc updated
3. End-to-end test: Gatekeeper blocks mismatch
4. Test Qdrant retrieval with MDX chunks
5. Gather feedback and iterate

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|:-----|:-------|:-----------|
| LLM hallucinates invalid MDX syntax | High | Add strict MDX validation with clear error messages |
| MDX parsing adds latency to Qdrant sync | Medium | Optimize parser, cache parsed results |
| Existing Markdown files need migration | Medium | Automated migration script, validate all outputs |
| `docs.json` becomes out of sync | High | Atomic updates (file + navigation in same commit) |
| MDX components don't render in all viewers | Low | Provide fallback Markdown rendering |
| Increased complexity for manual edits | Low | Clear documentation, but discourage manual edits anyway |
| **Raw MDX looks poor in GitHub UI** | **Medium** | **Accept trade-off: Add `make docs-preview` task for local rendering** |
| **Concurrent PR merge conflicts on `docs.json`** | **High** | **Git auto-merge handles JSON list appends; Agent rebases if conflict detected** |
| **Agent misinterprets natural language spec** | **High** | **Label Intent as "Interpreted Intent" with disclaimer; Link to source issue** |

---

## Success Metrics

### Quantitative
- **Retrieval Precision:** >90% of agent queries return the exact relevant chunk
- **Validation Pass Rate:** >95% of agent-generated MDX passes validation on first attempt
- **Navigation Coverage:** 100% of Twin Docs listed in `docs.json`
- **Chunking Quality:** Average chunk size 200-400 tokens (semantic boundaries)

### Qualitative
- **Agent Reasoning:** Agents can extract specific parameters without hallucination
- **Human Readability:** Engineers prefer MDX docs over Markdown tables
- **Gatekeeper Clarity:** PR comments clearly show Intent vs Reality
- **Discoverability:** No orphaned documentation files

---

## Alternatives Considered

### Alternative 1: Keep Markdown, Add YAML Frontmatter
**Pros:** Simpler, no MDX complexity  
**Cons:** Still brittle tables, poor chunking, no structured components  
**Decision:** Rejected - doesn't solve core problems

### Alternative 2: Use JSON Schema Instead of MDX
**Pros:** Pure data, easy to parse  
**Cons:** Not human-readable, no narrative documentation  
**Decision:** Rejected - loses documentation value

### Alternative 3: Use Mintlify's Full Stack (Hosted)
**Pros:** No infrastructure to maintain  
**Cons:** External dependency, latency, privacy concerns, cost  
**Decision:** Rejected - violates platform-first principles

### Alternative 4: Custom Documentation Format
**Pros:** Full control, optimized for platform  
**Cons:** Reinventing the wheel, no ecosystem support  
**Decision:** Rejected - MDX is proven and has tooling

---

## Conclusion

Adopting MDX with structured components strikes the right balance between:
- **Machine-readability** (for agents and vector search)
- **Human-readability** (for engineers during incidents)
- **Maintainability** (automated generation and validation)
- **Platform-first principles** (internal control, fast retrieval)

The proposed changes align with the "Zero-Touch" philosophy: infrastructure documentation should be as polished and structured as a commercial SaaS product, but optimized for platform engineering workflows.

---

## Addressing "Day 2" Operational Concerns

### 1. The "Raw View" Problem

**Concern:** Raw MDX with `<ParamField>` tags looks significantly worse in GitHub UI than Markdown tables.

**Philosophy Check:** ✅ **ACCEPTED TRADE-OFF**

**Rationale:**
- The "Product" (rendered docs) is for consumption
- The "Source" (MDX) is for the Agent
- Data Quality for Agents > Visual Aesthetics in GitHub UI

**Mitigation:**
```bash
# Add to Makefile
docs-preview:
	@echo "Starting local documentation preview..."
	cd artifacts && mintlify dev
	@echo "Preview available at http://localhost:3000"
```

**Usage:**
- Solo Founder reviewing PR can run `make docs-preview` to see rendered output
- CI can generate preview deployments for PRs (optional)
- GitHub UI shows raw MDX, but that's acceptable for platform engineers

**Decision:** Proceed with MDX. The structured data benefits outweigh the raw view aesthetics.

---

### 2. The `docs.json` Concurrency Risk

**Concern:** Two concurrent PRs adding different services will both try to append to the same group in `docs.json`, causing merge conflicts.

**Scenario:**
```
PR A: Adds Redis to "Infrastructure" group
PR B: Adds Dragonfly to "Infrastructure" group
Result: Merge conflict on docs.json when second PR merges
```

**Analysis:**

Git's auto-merge typically handles JSON list appends correctly **if they are on separate lines**:

```json
// Before
"pages": [
  "specs/postgres"
]

// PR A adds (line 3)
"pages": [
  "specs/postgres",
  "specs/redis"
]

// PR B adds (line 3)
"pages": [
  "specs/postgres",
  "specs/dragonfly"
]

// Git auto-merge result (usually succeeds)
"pages": [
  "specs/postgres",
  "specs/redis",
  "specs/dragonfly"
]
```

**Mitigation Strategy:**

1. **Format `docs.json` with one entry per line** (not compact JSON)
2. **Agent must detect merge conflicts** and rebase automatically
3. **Atomic guarantee:** If `docs.json` update fails, the entire PR fails (no orphaned files)

**Implementation:**
```python
def update_navigation_manifest(file_path, navigation_group):
    """
    Update docs.json with new file entry
    Handles concurrent updates via rebase
    """
    max_retries = 3
    for attempt in range(max_retries):
        try:
            # Read current docs.json from main branch
            docs_json = fetch_from_git("artifacts/docs.json", branch="main")
            manifest = json.loads(docs_json)
            
            # Find the target group
            for group in manifest["navigation"]["groups"]:
                if group["group"] == navigation_group:
                    # Add new page (without .mdx extension)
                    page_path = file_path.replace("artifacts/", "").replace(".mdx", "")
                    if page_path not in group["pages"]:
                        group["pages"].append(page_path)
                        break
            
            # Format with one entry per line (for better git merge)
            formatted_json = json.dumps(manifest, indent=2)
            
            # Attempt to commit
            commit_to_pr("artifacts/docs.json", formatted_json, pr_number, 
                        f"docs: add {file_path} to navigation")
            return True
            
        except MergeConflictError:
            if attempt < max_retries - 1:
                # Rebase and retry
                rebase_pr_branch()
                continue
            else:
                raise Exception(f"Failed to update docs.json after {max_retries} attempts")
```

**Decision:** Accept the risk. Git auto-merge handles most cases. Agent rebases on conflict.

---

### 3. The "Interpreted Intent" Ambiguity

**Concern:** The Agent must transpile natural language requirements (from GitHub issues) into YAML specs. This is a *projection*, not a copy-paste.

**Example:**

**GitHub Issue #123:**
> "We need to limit Postgres replicas to 3 for cost control. Storage should be 10Gi by default."

**Agent's Interpretation:**
```yaml
spec:
  parameters:
    replicas: 3  # Max 3 replicas
    storage: 10Gi
```

**The Risk:** The Agent might misinterpret the requirement. "Limit to 3" could mean:
- Default is 3, but can be overridden
- Maximum is 3, cannot exceed
- Recommended is 3, but not enforced

**Mitigation:**

1. **Explicit Labeling:** Always label the Intent side as "Interpreted Intent"
2. **Disclaimer:** Include a comment explaining this is the Agent's projection
3. **Source Link:** Always link back to the original GitHub issue
4. **Human Verification:** The Gatekeeper comment is a *proposal*, not a final judgment

**Updated Gatekeeper Output:**

```markdown
## ⚠️ Gatekeeper: Spec vs Code Mismatch Detected

**File:** `platform/03-intelligence/postgres.yaml`  
**Spec:** https://github.com/org/repo/issues/123  
**Twin Doc:** [View Documentation](link)

### Mismatches Found

<CodeGroup>
```yaml Interpreted Intent
# ⚠️ AGENT INTERPRETATION of GitHub Issue #123
# Original requirement: "Limit replicas to 3 for cost control"
# This is a PROJECTION by the Librarian Agent, not a direct copy
# Source: https://github.com/org/repo/issues/123
#
# If this interpretation is incorrect, please:
# 1. Update the GitHub issue with clearer requirements, OR
# 2. Override this check by commenting "@librarian override"

spec:
  parameters:
    replicas: 3  # ❌ INTERPRETED MAX: 3
    storage: 10Gi
```

```yaml Code (Reality)
# From platform/03-intelligence/postgres.yaml
spec:
  parameters:
    replicas: 5  # ❌ CODE ALLOWS: Up to 5
    storage: 10Gi
```
</CodeGroup>

### Analysis

| Parameter | Interpreted Intent | Code Reality | Status |
|:----------|:-------------------|:-------------|:-------|
| `replicas` | `3` (interpreted max) | `5` (actual max) | ⚠️ Potential Mismatch |
| `storage` | `10Gi` | `10Gi` | ✅ Aligned |

### Action Required

**Option 1:** If the Agent's interpretation is correct:
- Update the code to enforce `replicas <= 3`

**Option 2:** If the Agent's interpretation is incorrect:
- Clarify the requirement in [GitHub Issue #123](link)
- The Agent will re-evaluate on the next commit

**Option 3:** Override this check:
- Comment `@librarian override` if you believe the code is correct despite the mismatch
- This will be logged for audit purposes

### Why This Matters

The Gatekeeper exists to catch drift between business intent and technical implementation. However, the Agent's interpretation of natural language requirements may not always be perfect. This check is a **conversation starter**, not a final judgment.

---
*Posted by Librarian Agent | [Gatekeeper Documentation](link)*
```

**Agent Prompt Update:**

```markdown
When generating the "Interpreted Intent" side of the comparison:

1. **Label it clearly:** Use "Interpreted Intent" as the code block label
2. **Add disclaimer:** Include a comment explaining this is your projection
3. **Link to source:** Always include the GitHub issue URL
4. **Be conservative:** If the requirement is ambiguous, state the ambiguity
5. **Provide escape hatch:** Offer the "@librarian override" option

Example:
```yaml Interpreted Intent
# ⚠️ AGENT INTERPRETATION of GitHub Issue #123
# Original: "Limit replicas to 3 for cost control"
# Interpretation: Maximum of 3 replicas enforced
# Ambiguity: Unclear if this is a hard limit or recommendation
# Source: https://github.com/org/repo/issues/123
```

**Decision:** Accept that Agent interpretation may be imperfect. Make it transparent and provide override mechanism.

---

## Summary of Refinements

| Concern | Status | Resolution |
|:--------|:-------|:-----------|
| Raw MDX looks poor in GitHub UI | ✅ Accepted | Add `make docs-preview` for local rendering |
| Concurrent `docs.json` merge conflicts | ✅ Mitigated | Git auto-merge + Agent rebase on conflict |
| Agent misinterprets natural language | ✅ Transparent | Label as "Interpreted Intent" + override mechanism |

All three concerns have been addressed with practical mitigations that align with the platform-first philosophy.

---

## Approval Checklist

- [ ] Reviewed by Platform Team Lead
- [ ] Reviewed by Agent/AI Team
- [ ] Reviewed by Documentation Owner
- [ ] Security/Privacy concerns addressed
- [ ] Implementation timeline approved
- [ ] Resource allocation confirmed

---

## Next Steps After Approval

1. Update `requirements.md` with new requirements (MDX validation, navigation manifest)
2. Update `design.md` with MDX architecture and examples
3. Update `tasks.md` with implementation tasks
4. Create proof-of-concept with one composition
5. Gather feedback and iterate
6. Roll out to all compositions

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** Awaiting Review
