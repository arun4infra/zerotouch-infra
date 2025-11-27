# Bootstrap Secrets

This directory contains the ONE manual secret needed to bootstrap the platform.

## ESO Bootstrap Secret

External Secrets Operator needs a GitHub PAT to access GitHub Secrets.

### Setup Instructions

1. **Create GitHub PAT**:
   - Go to: https://github.com/settings/tokens
   - Generate new token (classic)
   - Scopes needed: `repo` (for private repos) or `public_repo` (for public repos)
   - Copy the token

2. **Create the secret**:
   ```bash
   cp eso-bootstrap-secret.yaml.example eso-bootstrap-secret.yaml
   # Edit and replace YOUR_GITHUB_PAT with actual token
   kubectl apply -f eso-bootstrap-secret.yaml
   ```

3. **Add secrets to GitHub**:
   - Go to: https://github.com/arun4infra/zerotouch-infra/settings/secrets/actions
   - Add these secrets:
     - `ESO_GITHUB_TOKEN` - Same GitHub PAT (for ESO to read other secrets)
     - `KAGENT_OPENAI_API_KEY` - OpenAI API key for kagent agents

## Why This Manual Step?

This is the "chicken and egg" problem: ESO needs a secret to read secrets from GitHub. This ONE secret must be created manually. After that, all other secrets are managed via ESO from GitHub.

## Security Notes

- The actual `eso-bootstrap-secret.yaml` file is in `.gitignore`
- Never commit secrets to Git
- Rotate the GitHub PAT regularly
- Use repository-level secrets, not organization-level
