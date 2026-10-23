# Pipelines

| File | What | Triggered by |
| --- | --- | --- |
| `validate.yml` | static checks only: gitleaks, fmt, markdownlint, validate + tflint (`stack`, `bootstrap`), checkov | push to `main` that is **not** a stack change (docs, `bootstrap/`, configs); every PR via branch policy |
| `infra.yml` | static checks → Plan → Apply (approval: `movies-infra`) → Outputs | push to `main` touching `stack/*.tf`, `stack/settings.tfvars`, `stack/.terraform.lock.hcl`, `backend.hcl` or the pipeline itself |
| `set-secret.yml` | manual, one-off: writes the TMDB token into Key Vault via the WIF service connection | manual only |
| `templates/static-checks.yml` | the shared static-check steps | included by `validate.yml` and `infra.yml` |

All of them run in the self-hosted pool `movies-pool`.

Editing `stack/README.md` or anything in `docs/` runs only `validate.yml`:
documentation never queues a Terraform plan or an approval.

## Setting a third-party secret

`set-secret.yml` writes the TMDB token into Key Vault. The vault has no
public endpoint, so this has to run on the agent; Terraform does not manage
the value, so it never reaches code or Terraform state.

1. *Pipelines → set-secret → Edit → Variables → New variable*:
   name `TMDB_READ_TOKEN`, value = the TMDB **API Read Access Token**,
   tick **Keep this value secret** → *OK* → **Save**.
2. *Run pipeline*. The first run asks to *Permit* `sc-movies-azure`.
3. When the run is green, delete the variable: *Edit → Variables →
   TMDB_READ_TOKEN → Delete → Save*. From now on the token lives only in
   Key Vault.

To rotate the token, repeat the three steps with the new value.

## Pull request validation

Azure Repos **ignores YAML `pr:` triggers**; PR runs come from branch
policies. *Repos → Branches → main → ⋮ → Branch policies → Build validation
→ +*:

| Build pipeline | Path filter | Policy | Why |
| --- | --- | --- | --- |
| `infra-validate` | *(empty: every PR)* | Required | lint and scan whatever the PR touches |
| `infra` | `/stack/*.tf; /stack/settings.tfvars; /stack/.terraform.lock.hcl; /backend.hcl; /pipelines/infra.yml` | Optional | shows the Terraform plan in the PR; Apply is skipped outside `main` |

Design rules:

- Every job runs on the self-hosted agent in the hub: state, Key Vault and SQL
  are reachable only through private endpoints.
- Terraform authenticates with the agent's managed identity; the
  `sc-movies-azure` service connection (workload identity federation) is
  used by Azure CLI tasks.
- The service connection is authorised **per pipeline**, never for all
  pipelines: the first run of each pipeline that uses it stops with
  *"This pipeline needs permission to access a resource"* until someone with
  rights on the connection clicks *Permit*. A pipeline added later cannot
  silently reach Azure.
- Plans contain secrets in clear text: they stay on the agent outside the
  workspace and are deleted after apply. They are never published as artifacts.
- Apply runs exactly the plan that was approved, and only from `main`.
- Only non-sensitive outputs leave the pipeline (artifact `stack-outputs`).
- Terraform manages the vault, not third-party secret values: the TMDB token
  goes in through `set-secret.yml` and, after its run, lives only in Key Vault.
