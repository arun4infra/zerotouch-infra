# Two-Agent Architecture Feedback: Validator + Documentor

**Date:** 2025-12-01  
**Status:** Analysis & Recommendation  
**Context:** Splitting Librarian into PR Reviewer (Validator) + PR Documentor

---

## Executive Summary

**Verdict: ✅ STRONGLY RECOMMENDED**

Splitting the Librarian into two specialized agents (Validator + Documentor) is an **excellent architectural decision** that aligns perfectly with the Zero-Touch philosophy and addresses several operational concerns.

**Key Benefits:**
1. **Fast Feedback Loop** - Validator blocks bad PRs in ~20-30s (before expensive doc generation)
2. **Clear Separation of Concerns** - Gatekeeper logic vs Documentation logic
3. **Independent Scaling** - Validator runs on every PR, Documentor only on valid PRs
4. **Easier Debugging** - Isolated failure domains
5. **Cost Optimization** - Don't waste LLM tokens on docs for PRs that will be blocked

---

## Architecture Analysis

### Proposed Flow

```
PR Event
   ↓
┌─────────────────────────────────────────────┐
│  Validator Agent (Fast Gate)                │
│  - Fetch PR diff (GitHub MCP)               │
│  - Fetch spec (GitHub MCP)                  │
│  - Compare Intent vs Reality                │
│  - Block if mismatch                        │
│  Time: ~20-30s                              │
└─────────────────────────────────────────────┘
   ↓ (only if passed)
┌─────────────────────────────────────────────┐
│  Documentor Agent (Twin Doc Writer)         │
│  - Search precedent (Qdrant MCP)            │
│  - Fetch existing doc (GitHub MCP)          │
│  - Generate/update markdown                 │
│  - Validate + commit (GitHub MCP)           │
│  - Post summary comment                     │
│  Time: ~1-3 min                             │
└─────────────────────────────────────────────┘
```

### ✅ Strengths

**1. Performance Optimization**
- Validator is a **fast gate** (~20-30s)
- Blocks invalid PRs before expensive doc generation
- Documentor only runs on valid PRs (saves compute)

**2. Clear Responsibilities**

| Agent | Role | Input | Output | Failure Mode |
|:------|:-----|:------|:-------|:-------------|
| **Validator** | Gatekeeper | PR diff + Spec URL | ✅ Pass / ❌ Block | Block PR with explanation |
| **Documentor** | Writer | Valid PR + Qdrant context | Twin Doc + Comment | Retry with iteration loop |

**3. Independent Failure Domains**
- If Validator fails → PR blocked (correct behavior)
- If Documentor fails → PR still valid, docs can be regenerated
- No cascading failures

**4. Scalability**
- Validator: Lightweight, stateless, fast
- Documentor: Heavier, stateful (Qdrant), slower
- Can scale independently based on load

**5. Cost Optimization**
- Validator uses minimal LLM tokens (just comparison logic)
- Documentor uses more tokens (generation + iteration)
- Don't waste tokens on docs for PRs that will be blocked

---

## Detailed Component Analysis

### 1. Validator Agent (PR Reviewer)

**Purpose:** Fast gate to block misaligned PRs

**Responsibilities:**
1. Extract Spec URL from PR description (or inline spec)
2. Fetch Spec content from GitHub
3. Fetch PR diff (changed files)
4. Identify Contract Boundary in changed files (Universal Mental Model)
5. Compare Intent (Spec) vs Reality (Code)
6. Block PR if mismatch detected
7. Post detailed Gatekeeper comment with `<CodeGroup>` comparison

**Key Characteristics:**
- **Fast:** ~20-30s execution time
- **Stateless:** No Qdrant dependency
- **Deterministic:** Same input → same output
- **Blocking:** Fails CI if mismatch detected

**MCP Tools Used:**
- `fetch_from_git` - Read spec and code files
- `github_api` - Post blocking comment

**Prompt Strategy:**
```markdown
You are the Gatekeeper. Your job is to validate that code changes align with business specs.

1. Read the Spec URL from the PR description
2. Identify the Contract Boundary in the changed files (ignore implementation details)
3. Compare Intent (Spec) vs Reality (Contract)
4. If misaligned, block the PR with a detailed explanation

Use the "Interpreted Intent" pattern:
- Label your interpretation clearly
- Add disclaimer
- Link to source
- Provide override mechanism
```

**Docker Image:**
```dockerfile
FROM python:3.11-slim
WORKDIR /agent
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY validator.py contract_extractor.py mcp_client.py ./
ENTRYPOINT ["python", "validator.py"]
```

**Estimated Resource Usage:**
- CPU: Low (mostly I/O bound)
- Memory: ~256MB
- LLM Tokens: ~2,000-5,000 per PR
- Execution Time: 20-30s

---

### 2. Documentor Agent (PR Documentor)

**Purpose:** Generate/update Twin Docs for valid PRs

**Responsibilities:**
1. Search Qdrant for similar documentation (precedent)
2. Fetch existing Twin Doc (if updating)
3. Fetch template (if creating new)
4. Extract Contract Boundary from changed files
5. Generate MDX with `<ParamField>` or `<Steps>` components
6. Validate MDX syntax
7. Update `docs.json` navigation
8. Commit to PR branch (atomic operation)
9. Post summary comment

**Key Characteristics:**
- **Slower:** ~1-3 min execution time
- **Stateful:** Depends on Qdrant for precedent search
- **Iterative:** Retries on validation errors (max 3 attempts)
- **Non-blocking:** Failures don't block PR (can be regenerated)

**MCP Tools Used:**
- `qdrant_find` - Search for similar docs
- `fetch_from_git` - Read existing docs and templates
- `upsert_twin_doc` - Atomic validate + write + commit
- `github_api` - Post summary comment

**Prompt Strategy:**
```markdown
You are the Documentation Writer. Your job is to create/update Twin Docs for valid PRs.

1. Search Qdrant for similar documentation patterns
2. Identify the Contract Boundary in the changed files
3. Generate MDX using structured components:
   - <ParamField> for specs
   - <Steps> for runbooks
   - <CodeGroup> for Intent vs Reality
4. Validate MDX syntax
5. Update docs.json navigation
6. Commit atomically

Follow the "Interpreted Intent" pattern when showing Intent vs Reality.
```

**Docker Image:**
```dockerfile
FROM python:3.11-slim
WORKDIR /agent
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY documentor.py mcp_client.py template_engine.py markdown_validator.py ./
ENTRYPOINT ["python", "documentor.py"]
```

**Estimated Resource Usage:**
- CPU: Medium (MDX parsing + validation)
- Memory: ~512MB
- LLM Tokens: ~10,000-20,000 per PR
- Execution Time: 1-3 min

---

## Workflow Integration

### GitHub Actions Workflow

```yaml
name: Librarian Pipeline

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - 'platform/**/*.yaml'
      - 'services/**/*.py'
      - 'docs/**/*.md'

jobs:
  validate:
    name: Validate Spec Alignment
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Run Validator
        uses: ./.github/actions/validator
        with:
          pr_number: ${{ github.event.pull_request.number }}
          github_token: ${{ secrets.GITHUB_BOT_TOKEN }}  # NOT default GITHUB_TOKEN
      
      # If validator fails, workflow stops here (PR blocked)

  document:
    name: Generate Twin Docs
    needs: validate  # Only runs if validation passes
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}  # Checkout PR branch
          token: ${{ secrets.GITHUB_BOT_TOKEN }}  # For commits
      
      - name: Run Documentor
        uses: ./.github/actions/documentor
        with:
          pr_number: ${{ github.event.pull_request.number }}
          github_token: ${{ secrets.GITHUB_BOT_TOKEN }}
          qdrant_url: ${{ secrets.QDRANT_MCP_URL }}
      
      # If documentor fails, PR is still valid (docs can be regenerated)
      # But we should notify the team
      
      - name: Notify on Failure
        if: failure()
        uses: ./.github/actions/notify-slack
        with:
          message: "Documentor failed for PR #${{ github.event.pull_request.number }}"
```

**Key Points:**

1. **Sequential Execution:** `document` job depends on `validate` job
2. **Early Exit:** If Validator fails, Documentor never runs
3. **GitHub Bot Token:** Use `GITHUB_BOT_TOKEN` (not default `GITHUB_TOKEN`) to trigger CI re-runs
4. **Failure Handling:** Validator failure blocks PR, Documentor failure notifies but doesn't block

---

## File Structure

```
.github/
├── actions/
│   ├── validator/
│   │   ├── Dockerfile
│   │   ├── action.yml
│   │   ├── validator.py              # Main orchestrator
│   │   ├── mcp_client.py             # MCP tool interface
│   │   ├── contract_extractor.py     # Universal Mental Model logic
│   │   ├── spec_parser.py            # Parse GitHub issues
│   │   └── requirements.txt
│   │
│   └── documentor/
│       ├── Dockerfile
│       ├── action.yml
│       ├── documentor.py             # Main orchestrator
│       ├── mcp_client.py             # MCP tool interface
│       ├── template_engine.py        # MDX template rendering
│       ├── mdx_validator.py          # MDX syntax validation
│       ├── navigation_updater.py     # docs.json management
│       └── requirements.txt
│
└── workflows/
    └── librarian.yml                 # Main workflow
```

---

## Comparison: Single Agent vs Two Agents

| Aspect | Single Agent (Current) | Two Agents (Proposed) |
|:-------|:----------------------|:---------------------|
| **Execution Time** | 1-3 min (always) | 20-30s (if blocked) or 1.5-3.5 min (if valid) |
| **Cost per PR** | High (always generates docs) | Low (blocked PRs skip doc generation) |
| **Failure Clarity** | Mixed (validation + doc errors) | Clear (separate failure domains) |
| **Debugging** | Complex (one big agent) | Simple (isolated components) |
| **Scalability** | Monolithic | Independent scaling |
| **Retry Logic** | Complex (retry everything) | Simple (retry only failed component) |
| **Developer Experience** | Slow feedback (wait for docs) | Fast feedback (blocked in 30s) |

---

## Potential Concerns & Mitigations

### Concern 1: Increased Complexity

**Issue:** Two agents means two codebases, two Docker images, two action definitions.

**Mitigation:**
- Shared libraries (`mcp_client.py`, `contract_extractor.py`)
- Clear separation of concerns makes each agent simpler
- Easier to test in isolation

**Verdict:** ✅ Acceptable trade-off. Complexity is managed, not increased.

---

### Concern 2: Validator False Positives

**Issue:** If Validator is too strict, it blocks valid PRs.

**Mitigation:**
- Provide `@librarian override` mechanism
- Log all blocks for review
- Iterate on Validator prompt based on false positive rate
- Target: <5% false positive rate

**Verdict:** ✅ Acceptable. Override mechanism provides escape hatch.

---

### Concern 3: Documentor Failures

**Issue:** If Documentor fails, Twin Doc is not created.

**Mitigation:**
- Documentor failure doesn't block PR (non-critical)
- Notify team via Slack/email
- Provide manual trigger: `@librarian regenerate-docs`
- Documentor can be re-run on merged PRs

**Verdict:** ✅ Acceptable. Docs can be regenerated without blocking development.

---

### Concern 4: Increased CI Time (for valid PRs)

**Issue:** Valid PRs now run two jobs sequentially (Validator + Documentor).

**Analysis:**
- Validator: 20-30s
- Documentor: 1-3 min
- **Total:** 1.5-3.5 min (vs 1-3 min for single agent)
- **Overhead:** ~30s

**Mitigation:**
- Acceptable overhead for better architecture
- Most PRs are valid, so this is the common case
- Blocked PRs save time (30s vs 3 min)

**Verdict:** ✅ Acceptable. Slight overhead for valid PRs, significant savings for invalid PRs.

---

### Concern 5: Shared Code Duplication

**Issue:** Both agents need `mcp_client.py`, `contract_extractor.py`.

**Mitigation:**

**Option 1: Shared Library (Recommended)**
```
.github/actions/
├── shared/
│   ├── mcp_client.py
│   ├── contract_extractor.py
│   └── requirements.txt
├── validator/
│   ├── Dockerfile  # COPY ../shared/*.py
│   └── validator.py
└── documentor/
    ├── Dockerfile  # COPY ../shared/*.py
    └── documentor.py
```

**Option 2: Python Package**
```
.github/actions/
├── librarian_common/  # Python package
│   ├── __init__.py
│   ├── mcp_client.py
│   └── contract_extractor.py
├── validator/
└── documentor/
```

**Verdict:** ✅ Use Option 1 (shared directory). Simpler for Docker builds.

---

## Recommended Enhancements

### 1. Add Manual Triggers

Allow developers to manually trigger agents:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]
  issue_comment:
    types: [created]

jobs:
  check-command:
    if: github.event_name == 'issue_comment'
    runs-on: ubuntu-latest
    steps:
      - name: Check for commands
        id: command
        run: |
          COMMENT="${{ github.event.comment.body }}"
          if [[ "$COMMENT" == "@librarian validate" ]]; then
            echo "command=validate" >> $GITHUB_OUTPUT
          elif [[ "$COMMENT" == "@librarian regenerate-docs" ]]; then
            echo "command=document" >> $GITHUB_OUTPUT
          elif [[ "$COMMENT" == "@librarian override" ]]; then
            echo "command=override" >> $GITHUB_OUTPUT
          fi
    outputs:
      command: ${{ steps.command.outputs.command }}

  validate:
    needs: check-command
    if: needs.check-command.outputs.command == 'validate' || github.event_name == 'pull_request'
    # ... validator steps

  document:
    needs: check-command
    if: needs.check-command.outputs.command == 'document'
    # ... documentor steps
```

**Commands:**
- `@librarian validate` - Re-run Validator
- `@librarian regenerate-docs` - Re-run Documentor
- `@librarian override` - Skip Validator (with audit log)

---

### 2. Add Metrics and Observability

Track agent performance:

```python
# In validator.py
import time
from prometheus_client import Counter, Histogram

validation_duration = Histogram('validator_duration_seconds', 'Validator execution time')
validation_blocks = Counter('validator_blocks_total', 'Total PRs blocked')
validation_passes = Counter('validator_passes_total', 'Total PRs passed')

@validation_duration.time()
def validate_pr(pr_number):
    # ... validation logic
    if mismatch_detected:
        validation_blocks.inc()
        return False
    else:
        validation_passes.inc()
        return True
```

**Metrics to Track:**
- Validator execution time
- Validator block rate
- Documentor execution time
- Documentor retry rate
- MDX validation error rate

---

### 3. Add Dry-Run Mode

For testing without committing:

```yaml
- name: Run Documentor (Dry Run)
  uses: ./.github/actions/documentor
  with:
    pr_number: ${{ github.event.pull_request.number }}
    github_token: ${{ secrets.GITHUB_BOT_TOKEN }}
    qdrant_url: ${{ secrets.QDRANT_MCP_URL }}
    dry_run: true  # Don't commit, just validate
```

---

### 4. Add Parallel Execution (Advanced)

For very large PRs with multiple changed files:

```yaml
document:
  name: Generate Twin Docs
  needs: validate
  runs-on: ubuntu-latest
  strategy:
    matrix:
      file: ${{ fromJson(needs.validate.outputs.changed_files) }}
  steps:
    - name: Document ${{ matrix.file }}
      uses: ./.github/actions/documentor
      with:
        file_path: ${{ matrix.file }}
        # ... other inputs
```

**Note:** Only useful if PRs typically change 5+ compositions. Otherwise, sequential is simpler.

---

## Implementation Checklist

### Phase 1: Validator Agent (Week 1)
- [ ] Create `actions/validator/` directory structure
- [ ] Implement `validator.py` orchestrator
- [ ] Implement `contract_extractor.py` (Universal Mental Model)
- [ ] Implement `spec_parser.py` (parse GitHub issues)
- [ ] Create Dockerfile
- [ ] Create `action.yml`
- [ ] Write unit tests
- [ ] Test with sample PRs

### Phase 2: Documentor Agent (Week 1-2)
- [ ] Create `actions/documentor/` directory structure
- [ ] Implement `documentor.py` orchestrator
- [ ] Implement `template_engine.py` (MDX generation)
- [ ] Implement `mdx_validator.py` (syntax validation)
- [ ] Implement `navigation_updater.py` (docs.json management)
- [ ] Create Dockerfile
- [ ] Create `action.yml`
- [ ] Write unit tests
- [ ] Test with sample PRs

### Phase 3: Shared Libraries (Week 2)
- [ ] Extract `mcp_client.py` to shared directory
- [ ] Extract `contract_extractor.py` to shared directory
- [ ] Update Dockerfiles to copy shared code
- [ ] Test both agents with shared libraries

### Phase 4: Workflow Integration (Week 2)
- [ ] Create `workflows/librarian.yml`
- [ ] Configure job dependencies (validate → document)
- [ ] Add manual trigger support (`@librarian` commands)
- [ ] Add failure notifications (Slack/email)
- [ ] Test end-to-end workflow

### Phase 5: Observability (Week 3)
- [ ] Add Prometheus metrics
- [ ] Create Grafana dashboard
- [ ] Configure alerts (high block rate, slow execution)
- [ ] Add logging (structured JSON logs)

### Phase 6: Testing and Rollout (Week 3)
- [ ] Test with 10 sample PRs (5 valid, 5 invalid)
- [ ] Measure execution times
- [ ] Measure false positive rate
- [ ] Gather developer feedback
- [ ] Roll out to all PRs

---

## Cost-Benefit Analysis

### Costs
- **Development Time:** ~3 weeks (vs ~2 weeks for single agent)
- **Maintenance:** Two codebases to maintain
- **CI Time:** +30s overhead for valid PRs

### Benefits
- **Fast Feedback:** Invalid PRs blocked in 30s (vs 3 min)
- **Cost Savings:** ~70% reduction in LLM tokens for invalid PRs
- **Better UX:** Developers get immediate feedback
- **Easier Debugging:** Isolated failure domains
- **Independent Scaling:** Optimize each agent separately

### ROI Calculation

**Assumptions:**
- 100 PRs per month
- 30% are invalid (blocked by Validator)
- Single agent: 3 min, 15,000 tokens per PR
- Validator: 30s, 3,000 tokens per PR
- Documentor: 2 min, 12,000 tokens per PR

**Single Agent:**
- Total time: 100 PRs × 3 min = 300 min
- Total tokens: 100 PRs × 15,000 = 1,500,000 tokens

**Two Agents:**
- Invalid PRs: 30 PRs × 30s = 15 min, 30 PRs × 3,000 = 90,000 tokens
- Valid PRs: 70 PRs × 2.5 min = 175 min, 70 PRs × 15,000 = 1,050,000 tokens
- Total time: 190 min (37% reduction)
- Total tokens: 1,140,000 tokens (24% reduction)

**Savings:**
- Time: 110 min/month
- Tokens: 360,000 tokens/month (~$7.20 at $0.02/1K tokens)
- Developer productivity: Faster feedback loop

**Verdict:** ✅ Clear ROI. Pays for itself in first month.

---

## Final Recommendation

**✅ STRONGLY RECOMMENDED**

The two-agent architecture (Validator + Documentor) is a **superior design** that:

1. **Improves Developer Experience** - Fast feedback (30s vs 3 min for invalid PRs)
2. **Reduces Costs** - 24% reduction in LLM token usage
3. **Simplifies Debugging** - Clear separation of concerns
4. **Enables Independent Scaling** - Optimize each agent separately
5. **Aligns with Zero-Touch Philosophy** - Fast, automated, reliable

**Next Steps:**
1. ✅ Approve this architecture
2. Update `design.md` with two-agent architecture
3. Update `tasks.md` with implementation tasks
4. Create proof-of-concept with sample PR
5. Roll out to production

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-01  
**Status:** ✅ Recommended for Approval
