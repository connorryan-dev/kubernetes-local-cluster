# Secrets Management with SOPS + age

This repo uses [SOPS](https://github.com/mozilla/sops) with [age](https://age-encryption.org/)
to manage Kubernetes Secrets securely in git, with Flux handling the decryption in-cluster.

## Overview

- **Age keypair** (`~/.config/sops/age/keys.txt`): lives locally on your machine, NEVER committed to git
- **SOPS-encrypted Secret** (e.g., `infrastructure/runners/github-runner-secret.sops.yaml`): safe to commit to git
- **`sops-age` Secret**: created once per cluster in `flux-system` namespace; Flux uses it to decrypt encrypted manifests

## Setting up age (one-time)

If you haven't already:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt
# Output:
# age1... (this is your public key)
# AGE-SECRET-KEY-1... (this is your private key, keep it secret)
```

Save the public key (e.g., `age1abc123...`) — you'll need it when encrypting secrets.

## Creating a new encrypted Secret

To create a new encrypted Secret (e.g., for a new app):

1. Create a plain Secret YAML file:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: my-secret
     namespace: my-namespace
   type: Opaque
   stringData:
     PASSWORD: my-password
   ```

2. Create a `.sops.yaml` configuration file in the repo root (if not already present):
   ```yaml
   creation_rules:
     - age: AGE1abc123def456...  # replace with your public key (from age-keygen)
       encrypted_regex: ^(stringData|data)$
   ```

3. Encrypt the file:
   ```bash
   sops -e -i my-secret.yaml
   # or for the YAML to remain named *.sops.yaml:
   sops -e my-secret.yaml > my-secret.sops.yaml
   ```

4. Verify it's encrypted (should contain `ENC[AES256_GCM,...]` instead of plaintext):
   ```bash
   cat my-secret.sops.yaml | head -20
   ```

5. Commit and push:
   ```bash
   git add my-secret.sops.yaml
   git commit -m "Add encrypted secret for my-secret"
   git push
   ```

6. In the Kustomization that uses this Secret, enable SOPS decryption:
   ```yaml
   spec:
     decryption:
       provider: sops
       secretRef:
         name: sops-age
   ```

## Editing an encrypted Secret

To edit a secret that's already encrypted:
```bash
sops my-secret.sops.yaml
```

This opens your `$EDITOR` with the decrypted content. When you save and exit,
SOPS automatically re-encrypts the file.

Verify the file is still encrypted before committing:
```bash
cat my-secret.sops.yaml | head -20  # should see ENC[AES256_GCM,...]
```

## Rotating the PAT (runner registration token)

The runner's GitHub PAT is stored in `infrastructure/runners/github-runner-secret.sops.yaml`.

To rotate it:

1. Generate a new PAT in GitHub:
   - Go to Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Create a new token with `repo` and `workflow` scopes
   - Copy the token value

2. Edit the encrypted Secret:
   ```bash
   sops infrastructure/runners/github-runner-secret.sops.yaml
   ```

3. Replace the value of `GITHUB_TOKEN` with the new PAT and save.

4. Commit and push:
   ```bash
   git add infrastructure/runners/github-runner-secret.sops.yaml
   git commit -m "Rotate runner GitHub PAT"
   git push
   ```

5. Trigger a Flux reconciliation to pick up the change:
   ```bash
   flux reconcile kustomization github-runners
   ```

6. Verify the runner pods restarted:
   ```bash
   kubectl rollout restart deployment/github-runner -n github-runners
   kubectl get pods -n github-runners --watch
   ```

## Troubleshooting

### "age: could not decrypt file"
- Ensure `~/.config/sops/age/keys.txt` exists and is readable
- Verify the public key in `.sops.yaml` matches your keypair
- Check that the file is actually encrypted (contains `ENC[AES256_GCM,...]`)

### "sops-age Secret not found"
- Create it in the `flux-system` namespace:
  ```bash
  kubectl create secret generic sops-age \
    -n flux-system \
    --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
  ```

### Flux logs show decryption failures
```bash
flux logs --all-namespaces | grep -i sops
```

Common causes:
- `sops-age` Secret missing or corrupted
- Public key in `.sops.yaml` doesn't match the private key in `keys.txt`
- File was encrypted with a different age key than what's in the cluster

### I accidentally committed an unencrypted Secret
1. Immediately revoke any credentials in that Secret (e.g., regenerate the PAT in GitHub)
2. Remove the file from git history (e.g., using `git filter-branch` or `BFG Repo-Cleaner`)
3. Encrypt the corrected version and re-commit

## References

- [SOPS documentation](https://github.com/mozilla/sops)
- [age documentation](https://age-encryption.org/)
- [Flux SOPS integration](https://fluxcd.io/flux/guides/mozilla-sops/)
