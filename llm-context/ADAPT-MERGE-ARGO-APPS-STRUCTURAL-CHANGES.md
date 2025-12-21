# Branch Merge Workflow for ArgoCD Target Revision Updates

## Overview

This document outlines the workflow for merging feature branches that contain ArgoCD `targetRevision` references when the branch structure or naming changes significantly.

## Background

ArgoCD applications use `targetRevision` to specify which Git branch/tag to sync from. When feature branches introduce new directory structures or significant changes, the ArgoCD manifests often reference the feature branch name directly. This creates a circular dependency during merge:

- **Problem**: Feature branch references itself in `targetRevision`
- **Issue**: After merge, ArgoCD tries to sync from a non-existent branch
- **Result**: CI failures and sync errors

## When This Workflow Is Needed

Use this workflow when:
- Feature branch introduces new ArgoCD application structures
- Branch contains `targetRevision` references to itself
- CI/CD depends on ArgoCD sync success
- Branch protection prevents direct deletion after merge

## Workflow Steps

### Phase 1: Prepare Feature Branch for Merge
1. **Update Target Revisions**: Change all `targetRevision` references from feature branch name to target branch (usually `main`)
2. **Disable Auto-Delete**: Turn off "Automatically delete head branches" in GitHub repository settings
3. **Test CI**: Ensure CI passes with updated target revisions
4. **Merge**: Merge feature branch to target branch

### Phase 2: Clean Up Target Branch
1. **Sync Local**: Pull latest changes from target branch
2. **Create Cleanup Branch**: Create new branch from updated target branch
3. **Verify References**: Ensure all `targetRevision` values point to target branch
4. **Enable Auto-Delete**: Re-enable "Automatically delete head branches" setting
5. **Merge Cleanup**: Merge cleanup branch to target branch

### Phase 3: Final Cleanup
1. **Manual Deletion**: Delete original feature branch manually
2. **Verify CI**: Confirm CI passes on target branch
3. **Document**: Update any relevant documentation

## Key Principles

- **Never merge with self-referencing target revisions**
- **Always test CI before final merge**
- **Use temporary branches for target revision updates**
- **Maintain branch protection settings appropriately**

## Tools

- Use existing update scripts (e.g., `update-target-revision.sh`) when available
- Leverage repository automation settings strategically
- Test in CI environment before production merge

## Common Pitfalls

- Forgetting to update target revisions before merge
- Leaving auto-delete enabled during complex merges
- Not testing CI with updated references
- Assuming ArgoCD will handle branch renames automatically

## Success Criteria

- CI passes on target branch after merge
- All ArgoCD applications sync successfully
- No orphaned branch references remain
- Repository settings restored to normal state

---

*This workflow ensures clean merges while maintaining ArgoCD functionality and CI stability.*