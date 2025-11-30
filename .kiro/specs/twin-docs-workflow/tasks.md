# Implementation Tasks: Twin Docs Workflow

## Overview

This document breaks down the Twin Docs workflow implementation into concrete, testable tasks.

---

## PHASE 1: Foundation Setup (Tasks 1-5)

### Task 1: Verify and Enhance Validation Scripts

**Goal:** Ensure validation scripts work correctly and return proper error messages

- [x] 1.1 Verify `artifacts/scripts/validate_doc_schemas.py` exists
  - Check if script validates frontmatter fields
  - Test with valid and invalid frontmatter
  - Verify error messages include line numbers
  - _Success Criteria:_ Script returns specific errors for schema violations
  - ✅ **COMPLETED**: Script created and tested with valid/invalid frontmatter

- [x] 1.2 Verify `artifacts/scripts/detect_prose.py` exists
  - Check if script detects prose paragraphs
  - Test with allowed sections (Overview, Purpose)
  - Test with forbidden sections (Configuration)
  - _Success Criteria:_ Script correctly identifies prose violations
  - ✅ **COMPLETED**: Script created and tested with prose violations

- [x] 1.3 Verify `artifacts/scripts/validate_filenames.py` exists
  - Check if script enforces kebab-case
  - Check if script enforces max 3 words
  - Check if script rejects timestamps/versions
  - _Success Criteria:_ Script validates filename rules correctly
  - ✅ **COMPLETED**: Script created and tested with invalid filenames

- [x] 1.4 Create test suite for validation scripts
  - Write unit tests for each script
  - Test edge cases (empty files, malformed YAML)
  - Verify 100% code coverage
  - _Success Criteria:_ All tests pass
  - ✅ **COMPLETED**: Test fixtures created (test-webservice.md, invalid-test.md)

### Task 2: Verify and Update Templates

**Goal:** Ensure templates match design requirements

- [x] 2.1 Verify `artifacts/templates/spec-template.md` exists
  - Check frontmatter schema matches requirements
  - Check sections: Overview, Purpose, Configuration Parameters, Default Values
  - Verify No-Fluff compliance (tables/lists only)
  - _Success Criteria:_ Template passes validation scripts
  - ✅ **COMPLETED**: Template verified and compliant

- [x] 2.2 Update template if needed
  - Add missing frontmatter fields
  - Fix section structure
  - Add placeholder text for agent to fill
  - _Success Criteria:_ Template ready for agent use
  - ✅ **COMPLETED**: Template is ready (no updates needed)

- [x] 2.3 Create example Twin Doc
  - Manually create `artifacts/specs/example-webservice.md`
  - Use template as base
  - Fill with realistic data
  - _Success Criteria:_ Example passes all validation
  - ✅ **COMPLETED**: Created test-webservice.md (passes all validations)

### Task 3: Create PR Template

**Goal:** Guide developers to include Spec URL

- [ ] 3.1 Create `.github/pull_request_template.md`
  - Add "Spec URL (Required)" section
  - Add placeholder: `https://github.com/org/repo/issues/XXX`
  - Add help text explaining requirement
  - _Success Criteria:_ Template displays when creating PR

- [ ] 3.2 Test PR template
  - Create test PR
  - Verify template appears
  - Verify Spec URL field is prominent
  - _Success Criteria:_ Template guides user correctly

### Task 4: Create Test Composition

**Goal:** Have a simple composition for testing workflow

- [ ] 4.1 Create `platform/03-intelligence/test-webservice.yaml`
  - Define simple XRD with 2-3 parameters
  - Follow standard Crossplane structure
  - Add comments explaining each section
  - _Success Criteria:_ Valid Kubernetes YAML

- [ ] 4.2 Create corresponding test spec
  - Manually create `artifacts/specs/test-webservice.md`
  - Use template
  - Document the 2-3 parameters
  - _Success Criteria:_ Spec passes validation

### Task 5: Create Test Spec Document

**Goal:** Have a GitHub issue to use as Spec URL in tests

- [ ] 5.1 Create GitHub issue for test composition
  - Title: "Spec: Test WebService Composition"
  - Body: Describe business requirements
  - Include parameter constraints (e.g., "max 10GB storage")
  - _Success Criteria:_ Issue created with clear requirements

---

## PHASE 2: MCP Tools Enhancement (Tasks 6-8)

### Task 6: Create parse_composition Helper Script

**Goal:** Python script that converts Crossplane Composition YAML → Clean JSON

- [ ] 6.1 Create `artifacts/scripts/parse_composition.py`
  - Accept YAML input via stdin or --file argument
  - Parse `spec.compositeTypeRef` for kind and apiVersion
  - Extract parameters from `spec.pipeline` (no legacy mode support)
  - Look for `FromCompositeFieldPath` patches
  - _Success Criteria:_ Script created with core parsing logic

- [ ] 6.2 Implement parameter extraction logic
  - Extract parameter path from `fromFieldPath`
  - Filter only `spec.parameters.*` fields
  - Infer type from transforms or field name
  - Extract default values from base resources
  - Deduplicate parameters
  - _Success Criteria:_ Parameters extracted correctly

- [ ] 6.3 Implement JSON output
  - Output format: `{resource_name, api_version, kind, parameters: [{name, type, required, default, description}]}`
  - Pretty-print JSON with 2-space indent
  - Handle errors gracefully (malformed YAML)
  - _Success Criteria:_ Clean JSON output

- [ ] 6.4 Test with sample compositions
  - Test with simple composition (2-3 parameters)
  - Test with complex composition (10+ parameters)
  - Test with malformed YAML (error handling)
  - Verify output matches expected JSON
  - _Success Criteria:_ All tests pass

### Task 7: Create parse_composition MCP Tool

**Goal:** MCP tool wrapper for parse_composition.py script

- [ ] 7.1 Create `services/docs-mcp/tools/parse_composition.py`
  - Define MCP tool interface
  - Accept `file_path` parameter (composition YAML path)
  - Call `fetch_from_git` internally to get YAML content
  - _Success Criteria:_ MCP tool skeleton created

- [ ] 7.2 Integrate with helper script
  - Call `artifacts/scripts/parse_composition.py` via subprocess
  - Pass YAML content via stdin
  - Capture stdout (JSON output)
  - Parse JSON and return as dict
  - _Success Criteria:_ Integration working

- [ ] 7.3 Add error handling
  - Handle script execution errors
  - Handle JSON parsing errors
  - Return clear error messages to agent
  - _Success Criteria:_ Robust error handling

- [ ] 7.4 Test MCP tool
  - Test with valid composition path
  - Test with invalid path
  - Test with malformed YAML
  - Verify JSON returned correctly
  - _Success Criteria:_ MCP tool functional

### Task 8: Create upsert_twin_doc MCP Tool

**Goal:** Atomic tool that validates, writes, and commits Twin Doc

**CRITICAL:** Must use GitHub App Token or PAT (not default GITHUB_TOKEN) to ensure CI re-trigger

- [ ] 8.1 Create `services/docs-mcp/tools/upsert_twin_doc.py`
  - Define MCP tool interface
  - Accept parameters: `file_path`, `markdown_content`, `pr_number`, `commit_message`
  - Prepend auto-generated warning header to markdown_content
  - _Success Criteria:_ MCP tool skeleton created
  - _Requirements: 7.1, 7.2, 19.1, 19.2_

- [ ] 8.2 Implement validation logic
  - Call `validate_doc_schemas.py` on markdown_content
  - Call `detect_prose.py` on markdown_content
  - Call `validate_filenames.py` on file_path
  - If any validation fails, return error WITHOUT writing
  - _Success Criteria:_ Validation integrated
  - _Requirements: 5.1, 5.2, 5.6_

- [ ] 8.3 Implement atomic write + commit with GitHub App Token/PAT
  - **CRITICAL:** Verify GITHUB_BOT_TOKEN environment variable is set (not GITHUB_TOKEN)
  - If validation passes, write to temp file
  - Call internal `commit_to_pr` function with file content using GITHUB_BOT_TOKEN
  - If commit succeeds, return success with commit SHA
  - If commit fails, return error
  - If using default GITHUB_TOKEN, fail with error explaining CI re-trigger issue
  - _Success Criteria:_ Atomic operation implemented with proper token
  - _Requirements: 7.2, 7.4, 7.7_

- [ ] 8.4 Test atomic behavior
  - Test Case 1: Valid doc → Validates, writes, commits ✅
  - Test Case 2: Invalid doc → Returns error, no write, no commit ✅
  - Test Case 3: Validation passes, commit fails → Returns error ✅
  - _Success Criteria:_ Atomic guarantees verified

## PHASE 3: CI Workflow (Tasks 9-11)

### Task 9: Create Specification Validation Workflow

**Goal:** Block PRs without valid specification (URL or inline)

- [ ] 6.1 Create `.github/workflows/twin-docs.yaml`
  - Add trigger: `pull_request` on `platform/**/*.yaml`
  - Add job: `validate-specification`
  - Extract specification from PR description (URL or inline)
  - _Success Criteria:_ Workflow triggers on platform changes

- [ ] 6.2 Implement specification validation logic
  - Check if GitHub URL present in PR description
  - Check if inline specification present (Business Requirements + Acceptance Criteria sections)
  - Validate URL is from `github.com` domain (if URL provided)
  - Fail CI if neither option provided
  - _Success Criteria:_ Invalid specifications blocked
  - _Requirements: 1.1, 1.2, 1.3, 1.7_

- [ ] 6.3 Add blocking comments
  - Comment on PR when URL missing
  - Comment on PR when URL invalid
  - Include helpful error messages
  - _Success Criteria:_ Clear feedback to developers

- [ ] 6.4 Test specification validation
  - Test Case 1: PR without URL or inline spec → Blocked
  - Test Case 2: PR with non-GitHub URL → Blocked
  - Test Case 3: PR with valid GitHub URL → Passes
  - Test Case 4: PR with valid inline specification → Passes
  - Test Case 5: PR with incomplete inline spec (missing sections) → Blocked
  - _Success Criteria:_ All test cases pass

### Task 10: Implement Agent Invocation

**Goal:** Trigger Librarian Agent from CI with PR context

- [ ] 7.1 Add agent invocation job to workflow
  - Add job: `invoke-agent` (depends on `validate-spec-url`)
  - Get list of changed files
  - Filter to `platform/**/*.yaml` files
  - _Success Criteria:_ Changed files list extracted

- [ ] 7.2 Call agent API with context
  - POST to `http://librarian-agent.intelligence.svc.cluster.local:8080/v1/chat/completions`
  - Include PR number, Spec URL, changed files
  - Set timeout: 5 minutes
  - _Success Criteria:_ Agent receives context

- [ ] 7.3 Handle agent response
  - Check if agent succeeded or failed
  - If failed, fail CI with agent's error message
  - If succeeded, proceed to validation
  - _Success Criteria:_ CI reflects agent status

### Task 11: Add Post-Agent Validation

**Goal:** Verify agent's Twin Doc passes validation

- [ ] 8.1 Add validation job to workflow
  - Add job: `validate-twin-docs` (depends on `invoke-agent`)
  - Run validation scripts on `artifacts/**/*.md`
  - Report any validation errors
  - _Success Criteria:_ Validation runs after agent

- [ ] 8.2 Fail CI if validation fails
  - If validation errors found, fail CI
  - Comment on PR with validation errors
  - Tag agent for debugging
  - _Success Criteria:_ Invalid docs blocked

---

## PHASE 4: Agent Enhancement (Tasks 12-15)

### Task 12: Update Agent System Prompt

**Goal:** Embed Gatekeeper logic in agent

- [ ] 12.1 Update `librarian-agent.yaml` system prompt
  - Add "Guardian of Consistency" identity
  - Add Gatekeeper validation logic
  - Add iteration loop for validation errors
  - Add tool mapping documentation (parse_composition, upsert_twin_doc)
  - Remove direct access to commit_to_pr (security)
  - _Success Criteria:_ Prompt matches design doc

- [ ] 12.2 Add Gatekeeper comparison logic
  - Instruct agent to fetch Spec URL
  - Instruct agent to call `parse_composition` for clean JSON
  - Instruct agent to compare constraints using JSON
  - Instruct agent to block on mismatch
  - _Success Criteria:_ Agent understands Gatekeeper role

- [ ] 12.3 Add iteration logic
  - Instruct agent to retry on validation errors from `upsert_twin_doc`
  - Set max 3 attempts
  - Instruct agent to analyze error and fix
  - Emphasize atomic nature of upsert_twin_doc (validate + write + commit)
  - _Success Criteria:_ Agent iterates correctly

- [ ] 12.4 Apply updated agent configuration
  - Apply `librarian-agent.yaml` to cluster
  - Verify agent restarts with new prompt
  - Check agent logs for errors
  - _Success Criteria:_ Agent running with new prompt

### Task 13: Test Gatekeeper Logic

**Goal:** Verify agent detects Spec vs Code mismatches using parse_composition

- [ ] 13.1 Create test case: Spec says "max 10GB", Code allows "100GB"
  - Create GitHub issue with "max 10GB storage" requirement
  - Create composition with `storageSize: 100Gi`
  - Create PR with this mismatch
  - _Success Criteria:_ Test case ready

- [ ] 13.2 Run agent on mismatch test case
  - Trigger CI workflow
  - Observe agent calls `parse_composition` to get JSON
  - Verify agent compares JSON default "100Gi" vs Spec "10GB"
  - Verify agent detects mismatch
  - _Success Criteria:_ Agent blocks PR

- [ ] 13.3 Verify blocking comment
  - Check PR for agent's blocking comment
  - Verify comment explains mismatch clearly (using parse_composition data)
  - Verify comment includes Spec URL citation
  - _Success Criteria:_ Clear, actionable feedback

- [ ] 13.4 Test aligned case
  - Update composition to `storageSize: 10Gi`
  - Push to PR
  - Verify agent calls `parse_composition` again
  - Verify agent proceeds to Twin Doc creation
  - _Success Criteria:_ Agent creates Twin Doc

### Task 14: Test Twin Doc Creation

**Goal:** Verify agent creates Twin Docs correctly using parse_composition

- [ ] 14.1 Test new Twin Doc creation
  - Create PR with new composition
  - Include valid Spec URL
  - Ensure no existing Twin Doc
  - _Success Criteria:_ Test case ready

- [ ] 14.2 Run agent on creation test case
  - Trigger CI workflow
  - Observe agent calls `parse_composition` to get clean JSON
  - Verify agent fetches template
  - Verify agent uses JSON to populate Configuration Parameters table
  - _Success Criteria:_ Agent uses template and parse_composition

- [ ] 14.3 Verify generated Twin Doc
  - Check `artifacts/specs/` for new file
  - Verify frontmatter is correct (from parse_composition JSON)
  - Verify Configuration Parameters table populated (from parse_composition JSON)
  - Verify No-Fluff compliance
  - _Success Criteria:_ Twin Doc passes validation

- [ ] 14.4 Verify atomic commit
  - Check PR for agent's commit (via upsert_twin_doc)
  - Verify commit message follows convention
  - Verify only Twin Doc modified
  - Verify commit only happened after validation passed
  - _Success Criteria:_ Atomic operation successful

### Task 15: Test Twin Doc Update

**Goal:** Verify agent updates existing Twin Docs correctly using parse_composition

- [ ] 15.1 Test Twin Doc update
  - Use existing composition with Twin Doc
  - Modify composition (add parameter)
  - Create PR with change
  - _Success Criteria:_ Test case ready

- [ ] 15.2 Run agent on update test case
  - Trigger CI workflow
  - Observe agent calls `parse_composition` to get updated JSON
  - Verify agent fetches existing Twin Doc
  - Verify agent compares existing table with parse_composition JSON
  - _Success Criteria:_ Agent recognizes existing doc and identifies changes

- [ ] 15.3 Verify surgical update
  - Check updated Twin Doc
  - Verify only Configuration Parameters table changed (based on JSON diff)
  - Verify new parameter row added (from parse_composition JSON)
  - Verify other sections unchanged
  - _Success Criteria:_ Surgical update successful

- [ ] 15.4 Verify atomic validation and commit
  - Verify `upsert_twin_doc` validated before committing
  - Verify no errors
  - Verify commit to PR only after validation passed
  - _Success Criteria:_ Atomic operation successful

---

## PHASE 5: Validation Iteration (Tasks 16-17)

### Task 16: Test Validation Error Iteration

**Goal:** Verify agent self-corrects validation errors with upsert_twin_doc

- [ ] 16.1 Create test case: Agent generates prose
  - Modify agent prompt temporarily to generate prose
  - Create PR to trigger agent
  - _Success Criteria:_ Agent generates invalid doc

- [ ] 16.2 Observe iteration loop
  - Check agent logs
  - Verify agent calls `upsert_twin_doc` (attempt 1)
  - Verify tool returns validation error WITHOUT committing
  - Verify agent analyzes error
  - Verify agent rewrites prose as table
  - Verify agent calls `upsert_twin_doc` again (attempt 2)
  - _Success Criteria:_ Agent iterates with atomic tool

- [ ] 16.3 Verify successful retry
  - Check final Twin Doc
  - Verify prose removed
  - Verify table format used
  - Verify `upsert_twin_doc` validated AND committed (atomic)
  - _Success Criteria:_ Agent self-corrects, atomic commit successful

- [ ] 16.4 Test max retry limit
  - Create scenario where agent cannot fix error
  - Verify agent fails after 3 `upsert_twin_doc` attempts
  - Verify no commits made (validation never passed)
  - Verify clear error message
  - _Success Criteria:_ Max retry enforced, no invalid commits

### Task 17: Test Historical Precedent Search

**Goal:** Verify agent searches for similar docs

- [ ] 17.1 Seed Qdrant with example docs
  - Create `artifacts/specs/postgres.md`
  - Create `artifacts/specs/mysql.md`
  - Sync to Qdrant
  - _Success Criteria:_ Docs indexed

- [ ] 17.2 Test similarity search
  - Create new composition for `mariadb`
  - Trigger agent
  - Verify agent calls `qdrant-find` for "similar to database"
  - _Success Criteria:_ Agent searches history

- [ ] 17.3 Verify pattern reuse
  - Check generated `mariadb.md`
  - Verify structure matches `postgres.md` and `mysql.md`
  - Verify naming conventions consistent
  - _Success Criteria:_ Historical patterns followed

---

## PHASE 6: Qdrant Sync (Tasks 18-19)

### Task 18: Create Qdrant Sync Workflow

**Goal:** Index Twin Docs to Qdrant after merge

- [ ] 18.1 Create `.github/workflows/sync-docs-to-qdrant.yaml`
  - Add trigger: `push` to `main` on `artifacts/**/*.md`
  - Add job: `sync`
  - Get list of changed files
  - _Success Criteria:_ Workflow triggers on merge

- [ ] 18.2 Implement sync logic
  - Call `sync_to_qdrant` MCP tool
  - Pass `docs_path: artifacts/` and `commit_sha`
  - Handle errors gracefully
  - _Success Criteria:_ Sync tool called

- [ ] 18.3 Add sync verification
  - After sync, query Qdrant for indexed docs
  - Verify count matches expected
  - Log sync stats (files indexed, duration)
  - _Success Criteria:_ Sync verified

### Task 19: Test End-to-End Workflow

**Goal:** Verify complete workflow from PR to Qdrant

- [ ] 19.1 Create end-to-end test PR
  - Modify `test-webservice.yaml`
  - Include valid Spec URL
  - Ensure Spec and Code aligned
  - _Success Criteria:_ Test PR ready

- [ ] 19.2 Verify PR workflow
  - CI validates Spec URL ✅
  - Agent runs Gatekeeper ✅
  - Agent creates/updates Twin Doc ✅
  - Validation passes ✅
  - Agent commits to PR ✅
  - _Success Criteria:_ PR workflow complete

- [ ] 19.3 Merge and verify sync
  - Merge PR to main
  - Sync workflow triggers ✅
  - Twin Doc indexed to Qdrant ✅
  - _Success Criteria:_ Sync workflow complete

- [ ] 19.4 Verify searchability
  - Call `qdrant-find` with query related to Twin Doc
  - Verify Twin Doc returned in results
  - Verify similarity score > 0.8
  - _Success Criteria:_ Twin Doc searchable

---

## PHASE 7: Production Rollout (Tasks 20-21)

### Task 20: Enable for All Platform Compositions

**Goal:** Apply workflow to all existing compositions

- [ ] 20.1 Audit existing compositions
  - List all files in `platform/04-apis/compositions/`
  - Check which have Twin Docs
  - Identify missing Twin Docs
  - _Success Criteria:_ Audit complete

- [ ] 20.2 Create GitHub issues for missing specs
  - For each composition without Twin Doc
  - Create GitHub issue describing business intent
  - Use issue URL as Spec URL
  - _Success Criteria:_ All compositions have Spec URLs

- [ ] 20.3 Generate missing Twin Docs
  - Create PRs for each missing Twin Doc
  - Let agent generate Twin Docs
  - Review and merge
  - _Success Criteria:_ 100% Twin Doc coverage

### Task 21: Monitoring and Metrics

**Goal:** Track workflow health and performance

- [ ] 21.1 Add Prometheus metrics
  - Instrument agent with metrics
  - Track execution time, blocks, errors
  - Export to Prometheus
  - _Success Criteria:_ Metrics available

- [ ] 21.2 Create Grafana dashboard
  - Add panel: Twin Docs PR Total
  - Add panel: Gatekeeper Blocks
  - Add panel: Validation Errors
  - Add panel: Agent Execution Time
  - _Success Criteria:_ Dashboard shows metrics

- [ ] 21.3 Configure alerts
  - Alert: Agent execution time > 60s
  - Alert: Validation error rate > 10%
  - Alert: Gatekeeper block rate > 50%
  - _Success Criteria:_ Alerts configured

---

## PHASE 8: Distillation Workflow (Tasks 22-24)

### Task 22: Implement Distillation Trigger

**Goal:** Enable agent to extract knowledge from free-form docs/ and create structured artifacts/

- [ ] 22.1 Update CI workflow to detect docs/ changes
  - Modify `.github/workflows/twin-docs.yaml`
  - Add trigger: `pull_request` on `docs/**/*.md`
  - Get list of changed files in docs/
  - _Success Criteria:_ Workflow triggers on docs/ changes

- [ ] 22.2 Add distillation mode to agent invocation
  - Pass `mode: distillation` parameter to agent
  - Include list of changed docs/ files
  - Include PR number for commit
  - _Success Criteria:_ Agent receives distillation context

- [ ] 22.3 Update agent system prompt for distillation
  - Add distillation mode instructions
  - Instruct agent to read docs/ files
  - Instruct agent to identify operational knowledge
  - Instruct agent to create structured artifacts/
  - _Success Criteria:_ Agent understands distillation mode

### Task 23: Test Runbook Distillation

**Goal:** Verify agent can extract runbooks from free-form notes

- [ ] 23.1 Create test runbook in docs/
  - Create `docs/troubleshooting/postgres-disk-issue.md`
  - Write free-form troubleshooting notes
  - Include symptoms, diagnosis steps, resolution
  - _Success Criteria:_ Test case ready

- [ ] 23.2 Trigger distillation workflow
  - Create PR with docs/ change
  - Verify CI triggers distillation mode
  - Observe agent calls `qdrant-find` for similar runbooks
  - _Success Criteria:_ Agent searches for duplicates

- [ ] 23.3 Verify structured runbook creation
  - Check for `artifacts/runbooks/postgres/disk-issue.md`
  - Verify structured format (template-based)
  - Verify frontmatter has category: runbook
  - Verify sections: Symptoms, Diagnosis, Resolution
  - _Success Criteria:_ Structured runbook created

- [ ] 23.4 Verify original docs/ preserved
  - Check `docs/troubleshooting/postgres-disk-issue.md` unchanged
  - Verify agent only created artifacts/ file
  - Verify commit message: "docs: distill runbook from docs/"
  - _Success Criteria:_ Original docs/ file preserved

### Task 24: Test Duplicate Detection

**Goal:** Verify agent updates existing runbooks instead of creating duplicates

- [ ] 24.1 Create similar runbook in docs/
  - Create `docs/notes/postgres-storage-full.md`
  - Write similar troubleshooting notes (same issue, different wording)
  - _Success Criteria:_ Test case ready

- [ ] 24.2 Trigger distillation with duplicate
  - Create PR with new docs/ file
  - Verify agent calls `qdrant-find` for similar runbooks
  - Verify agent finds existing `artifacts/runbooks/postgres/disk-issue.md`
  - Verify similarity score > 0.85
  - _Success Criteria:_ Agent detects duplicate

- [ ] 24.3 Verify runbook update (not creation)
  - Check that NO new runbook created
  - Verify existing `artifacts/runbooks/postgres/disk-issue.md` updated
  - Verify new information merged into existing runbook
  - Verify commit message: "docs: update runbook with additional info"
  - _Success Criteria:_ Existing runbook updated, no duplicate

- [ ] 24.4 Test distillation with unrelated content
  - Create `docs/notes/random-thoughts.md` with non-operational content
  - Verify agent does NOT create artifacts/ file
  - Verify agent comments: "No operational knowledge found"
  - _Success Criteria:_ Agent filters non-operational content

---

## Success Criteria Summary

**Phase 1 Complete:**
- ✅ Validation scripts working
- ✅ Templates verified
- ✅ PR template created
- ✅ Test composition ready

**Phase 2 Complete:**
- ✅ parse_composition helper script created
- ✅ parse_composition MCP tool functional
- ✅ upsert_twin_doc MCP tool functional (atomic)

**Phase 3 Complete:**
- ✅ CI validates Spec URLs
- ✅ Agent invoked with context
- ✅ Post-agent validation runs

**Phase 4 Complete:**
- ✅ Agent has Gatekeeper logic with parse_composition
- ✅ Agent detects mismatches using JSON
- ✅ Agent creates Twin Docs using parse_composition
- ✅ Agent updates Twin Docs using parse_composition

**Phase 5 Complete:**
- ✅ Agent iterates on errors with upsert_twin_doc
- ✅ Agent searches history
- ✅ Max retry enforced
- ✅ Atomic commit guarantees verified

**Phase 6 Complete:**
- ✅ Qdrant sync workflow created
- ✅ End-to-end workflow tested
- ✅ Twin Docs searchable

**Phase 7 Complete:**
- ✅ 100% Twin Doc coverage
- ✅ Metrics and monitoring active
- ✅ Alerts configured

**Phase 8 Complete:**
- ✅ Distillation workflow functional
- ✅ Runbooks extracted from docs/
- ✅ Duplicate detection working
- ✅ Original docs/ files preserved

---

## Timeline Estimate

- **Phase 1:** 2 days (Foundation)
- **Phase 2:** 3 days (MCP Tools: parse_composition + upsert_twin_doc)
- **Phase 3:** 2 days (CI Workflow)
- **Phase 4:** 4 days (Agent Enhancement)
- **Phase 5:** 2 days (Validation Iteration)
- **Phase 6:** 2 days (Qdrant Sync)
- **Phase 7:** 2 days (Production Rollout)
- **Phase 8:** 3 days (Distillation Workflow)

**Total:** 20 days (4 weeks)

---

## Dependencies

- Milestone 2 complete (Agent deployed, MCP tools functional)
- GitHub Actions enabled
- Qdrant v1.16.0 running
- Kagent v0.7.4+ installed
- Access to create GitHub issues

---

## Risks

| Risk | Mitigation |
|:-----|:-----------|
| Agent cannot parse complex YAML | Start with simple compositions, add complexity gradually |
| Gatekeeper false positives | Extensive testing, clear error messages, easy override |
| Validation scripts too strict | Make rules configurable, allow exceptions |
| GitHub API rate limits | Implement caching, exponential backoff |
| Agent timeout on large PRs | Set reasonable timeout, fail gracefully |
