# Stack layer

Everything the workload needs, applied **only** by `pipelines/infra.yml` on the
self-hosted agent (managed identity, remote state key `stack.tfstate`).
Values from bootstrap are read from bootstrap's own state
(`terraform_remote_state`), never copied by hand.

| File | What |
| --- | --- |
| `network.tf` | spoke VNet `10.20.0.0/16`, NSGs, hub ↔ spoke peering, spoke links to the shared private DNS zones |
| `dns.tf` | public zone `domain_name` (e.g. `movies.example.com`), alias A record, CAA (Let's Encrypt only) |
| `compute.tf` | app VM (Arm64, Ubuntu 24.04), its user-assigned identity, Azure Monitor Agent, Ansible SSH key |
| `data.tf` | Azure SQL Basic (Entra-only), Storage (blob/queue/table, no keys), private endpoints |
| `keyvault.tf` | Key Vault (RBAC, private); Terraform-generated secrets: session secret, Entra client secret, Ansible key |
| `entra.tf` | app registration for admin sign-in (owned by the agent identity) |
| `rbac.tf` | every role assignment of the stack (all inside the bootstrap ABAC allow-list) |
| `monitoring.tf` | Log Analytics (daily cap), Application Insights (Entra-only ingestion), DCR, Managed Grafana |
| `outputs.tf` | non-sensitive values for movies-configuration and movies-app |
| `settings.tfvars` | committed, non-secret settings (`domain_name`, `admin_object_id`, `app_admin_object_ids`) |

## First run

1. Fill in `settings.tfvars`: `domain_name` and the object IDs. Your own
   object ID:

   ```bash
   az ad signed-in-user show --query id -o tsv
   ```

2. Generate the provider lock file for both platforms and commit it
   (works without state access):

   ```bash
   cd stack
   terraform init -backend=false
   terraform providers lock -platform=linux_arm64 -platform=darwin_arm64
   ```

3. Azure DevOps → *Pipelines → New pipeline → Azure Repos Git → movies-infra →
   Existing YAML file → `/pipelines/infra.yml`*, save it as **`infra`**.
   No variables are needed.
4. Run. The first run pauses **twice**, both times by design:
   - **Plan stage, "This pipeline needs permission to access a resource"**:
     the pipeline asks to use the service connection `sc-movies-azure`.
     Check that the resource is exactly `sc-movies-azure`, then *View →
     Permit → Permit*. This authorises **this pipeline only**, once, for all
     future runs. Bootstrap deliberately does not grant the connection to
     all pipelines, so every new pipeline (for example `set-secret.yml`) asks
     again.
   - **Apply stage, approval on `movies-infra`**: read the plan in the
     Plan stage log first, then *Review → Approve*. This happens on every
     run that changes infrastructure.
5. From the **Outputs** stage log, copy `dns_name_servers` and add them as
   4 **NS** records for `domain_name` in its parent zone. For
   `movies.example.com` at Cloudflare: zone `example.com`, name `movies`,
   *DNS only* (not proxied). Check the delegation; it must return the same
   four Azure name servers:

   ```bash
   dig +short NS movies.example.com   # your domain_name
   ```

6. Put the TMDB token into Key Vault with the one-off pipeline
   `/pipelines/set-secret.yml`, see
   [Setting a third-party secret](../pipelines/README.md#setting-a-third-party-secret).

## Things that need time

- The first apply waits 90 s for Key Vault RBAC to propagate before writing secrets.
- DNS delegation can take a few minutes to become visible.
