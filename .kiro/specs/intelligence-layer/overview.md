# Design Document: Agentic-Native Infrastructure Architecture

## 1. Overview
This document defines the architecture for the "Intelligence Layer" of the Agentic-Native Infrastructure. The goal is to enable a **Solo Founder** to operate a complex Kubernetes platform via natural language, with a **"Silent Partner"** agent handling operations, documentation, and troubleshooting autonomously.

## 2. Core Principles
1.  **Single Source of Truth:** The Git Monorepo (`infra-platform`) holds both the Code (Manifests) and the Brain (Docs). Git is the **only** authoritative source for documentation versions.
2.  **Vector Knowledge Base:** A Vector Database (Qdrant) provides semantic search to **locate** relevant documents. Qdrant stores only metadata and embeddings; the Agent retrieves actual documentation content from Git. (See `docs/architecture/002-qdrant-as-index-not-store.md`)
3.  **Silent Partner Protocol:** The Agent filters noise. It proactively fixes issues and only notifies the human on **Success (PR Ready)**, **Failure**, or **High Risk**.
4.  **Automated Librarian:** Documentation is updated automatically by the Agent during Pull Requests to prevent "Doc Drift."
5.  **Solo Founder Constitution:** Simplicity and "Crash-Only" recovery take precedence over complex tooling.

## 3. System Architecture

### 3.1 Components
| Component | Implementation | Purpose |
| :--- | :--- | :--- |
| **Agent Engine** | **Kagent** | The orchestrator managing tools and reasoning. |
| **Long-Term Memory** | **Qdrant** | Vector DB storing embeddings and metadata for semantic search. Retrieves pointers to docs; Agent fetches content from Git. |
| **Tool Protocol** | **MCP** (Model Context Protocol) | Standard interface for Agent to access K8s, Git, and Qdrant. |
| **Ingestion Pipeline** | **GitHub Actions** | Automatically chunks and indexes `docs/` metadata to Qdrant on merge to `main`. |
| **Interface** | **Slack** &amp; **GitHub** | Chat for queries; PRs for operations. |

### 3.2 Directory Structure (The "Brain")
The `docs/` directory is structured for machine readability using strict Frontmatter.

```text
infra-platform/
├── docs/
│   ├── .meta/                 # Embeddings config & chunks
│   ├── architecture/          # "The Why" (Decision Records)
│   │   └── 001-why-talos.md
│   ├── runbooks/              # "The How" (Troubleshooting)
│   │   └── postgres-volume-full.md
│   └── specs/                 # "The What" (Twin Docs for Platform Resources)
│       └── webservice.md      # Maps to platform/04-apis/compositions/webservice.yaml
```

## 4. Communication Protocol

### 4.1 Mode A: The Consultant (Synchronous)
*   **Trigger:** Human asks a question in Slack (e.g., "How do I add a Redis cache?").
*   **Action:** Kagent searches Qdrant for relevant docs → Fetches actual content from Git → Synthesizes answer based on *approved* patterns → Generates YAML or answers.
*   **Goal:** Instant architectural guidance.

### 4.2 Mode B: The SRE (Asynchronous & Silent)
*   **Trigger:** Alert (Robusta) or Human Request.
*   **Action:** Kagent analyzes -> Fixes via Code -> Opens PR.
*   **Notification Logic:**
    *   **Routine Fix:** Notify only when PR is created (e.g., "✅ PR #42 created to scale CPU").
    *   **Unknown Issue:** Notify immediately (e.g., "⚠️ Escalation: No runbook found for Error X").
    *   **High Risk:** Notify immediately (e.g., "🛑 Risk Warning: PR #43 involves deleting storage").
*   **Debate:** Feedback is handled via **GitHub PR Comments**, preserving the decision log.

## 5. Documentation Strategy ("The Automated Librarian")

### 5.1 The Rule
**No human manual updates for routine specs.** The Agent updates the documentation within the same PR as the code change.

### 5.2 The Librarian Logic
The "Librarian Agent" runs on every PR. It adheres to a strict "No-Fluff" policy (Tables/Lists only, no verbal paragraphs).

#### A. Spec Synchronization (Twin Docs)
*   **Trigger:** Change in `platform/**/<name>.yaml`.
*   **Target:** `docs/specs/<name>.md`.
*   **Action:**
    1.  Parse the YAML schema/values.
    2.  Update the **Configuration Table** in the Markdown.
    3.  Update **Default Values**.

#### B. Runbook Generation (Operational Learning)
*   **Trigger:** PR fixes a specific Alert/Incident.
*   **Target:** `docs/runbooks/<component>-<error>.md`.
*   **Action:**
    1.  If new issue: Create file using **Runbook Template**.
    2.  If existing: Append to **Troubleshooting Matrix**.

## 6. Implementation Artifacts Required

1.  **`kagent/platform-sre.yaml`**: The SRE Agent definition (with "Silent Partner" prompt).
2.  **`kagent/librarian-agent.yaml`**: The Documentation Agent definition (with "No-Fluff" prompt).
3.  **`.github/workflows/librarian.yaml`**: The pipeline triggering doc updates on PRs.
4.  **`ingestion/sync_docs.py`**: The script indexing Markdown metadata and embeddings to Qdrant (content remains in Git).
5.  **`docs/templates/`**: Strict templates for Runbooks and Specs.