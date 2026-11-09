# Documenter deployment

This page records the repository-side setup for deploying the documentation
with Documenter.jl. It is the command-line (方式二) procedure used for PiKit.

## What gets configured

Two different GitHub settings are required:

| Item | GitHub location | Value |
|---|---|---|
| Deploy key | Settings → Deploy keys | Public SSH key, **Allow write access** enabled |
| `DOCUMENTER_KEY` | Settings → Secrets and variables → Actions → Repository secrets | Base64-encoded **private** SSH key, no whitespace |

The deploy key grants write access so Documenter can push the `gh-pages`
branch. The secret is how the workflow receives that private key.

## Procedure

### 1. Generate an SSH key pair

```sh
umask 077
ssh-keygen -t ed25519 -C "documenter PiKit.jl" -N "" -f /tmp/pikit-docs-key
```

This creates:

- `/tmp/pikit-docs-key` — private key
- `/tmp/pikit-docs-key.pub` — public key

The key must be generated without a passphrase because the CI job is
non-interactive.

### 2. Add the public key as a deploy key

Using GitHub CLI:

```sh
gh repo deploy-key add /tmp/pikit-docs-key.pub \
  --repo lysharedfuture/PiKit.jl \
  --title documenter \
  --allow-write
```

Equivalent UI path:

```text
https://github.com/lysharedfuture/PiKit.jl/settings/keys
```

Click **Add deploy key**, paste the public key, and check
**Allow write access**.

### 3. Add the private key as an Actions secret

Linux:

```sh
base64 -w0 /tmp/pikit-docs-key > /tmp/pikit-docs-key.b64
gh secret set DOCUMENTER_KEY \
  --repo lysharedfuture/PiKit.jl \
  < /tmp/pikit-docs-key.b64
```

macOS:

```sh
base64 < /tmp/pikit-docs-key | tr -d '\n' > /tmp/pikit-docs-key.b64
gh secret set DOCUMENTER_KEY \
  --repo lysharedfuture/PiKit.jl \
  < /tmp/pikit-docs-key.b64
```

Equivalent UI path:

```text
https://github.com/lysharedfuture/PiKit.jl/settings/secrets/actions
```

Click **New repository secret**:

- Name: `DOCUMENTER_KEY`
- Secret: the base64 private key, with no line breaks and no surrounding quotes

Use **Repository secrets**, not environment secrets or variables.

### 4. Remove local private-key material

```sh
rm -f /tmp/pikit-docs-key /tmp/pikit-docs-key.b64
```

### 5. Configure GitHub Pages

After the first successful deployment, set:

```text
https://github.com/lysharedfuture/PiKit.jl/settings/pages
```

- Source: **Deploy from a branch**
- Branch: `gh-pages`
- Folder: `/ (root)`

Documenter creates the `gh-pages` branch automatically on the first deploy.

### 6. TagBot

`TagBot` uses `DOCUMENTER_KEY` so a TagBot-created tag can trigger the
documentation workflow:

```yaml
- uses: JuliaRegistries/TagBot@v1
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    ssh: ${{ secrets.DOCUMENTER_KEY }}
```

## Verification

```sh
gh run list --repo lysharedfuture/PiKit.jl --workflow Docs
gh secret list --repo lysharedfuture/PiKit.jl
gh repo deploy-key list --repo lysharedfuture/PiKit.jl
```

Expected deployed pages:

- https://lysharedfuture.github.io/PiKit.jl/
- https://lysharedfuture.github.io/PiKit.jl/dev/

A successful deploy creates the `gh-pages` branch and reports:

```json
{"status":"built","source":{"branch":"gh-pages","path":"/"}}
```

## Troubleshooting

- If the workflow log shows `ENV["DOCUMENTER_KEY"] exists`, the SSH deploy
  key path is being used.
- If it shows `ENV["GITHUB_TOKEN"] exists` instead, the secret did not reach
  the job. Check that it is a repository secret and that the workflow step
  exports it.
- If the deploy key is read-only, Documenter cannot push `gh-pages`.
- The base64 private key must have no whitespace. Do not print it in logs or
  commit it.
