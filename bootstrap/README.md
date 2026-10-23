# Bootstrap layer

Creates everything the pipelines need before a pipeline can run:

| Resource | Why it cannot come from a pipeline |
| --- | --- |
| Terraform state storage (+ private endpoint) | state has to exist before any remote `terraform init` |
| Hub VNet, NSGs, private DNS zones | the agent and the state endpoint live in them |
| Network Watcher | one per region; must exist before the first VNet, or Azure auto-creates `NetworkWatcherRG` |
| Build agent VM + user-assigned identity | a pipeline cannot create the agent it runs on |
| Agent RBAC + Microsoft Graph permission | granting rights needs a more privileged identity than the agent |
| Azure DevOps pool, service connection, environments | the pipelines reference them |
| Empty `rg-movies-app` | the agent's rights are scoped to it before the stack exists |

It runs **once**, by a human, from their **own machine** (`az login`), then
moves its own state into the storage account it just created.

## Prerequisites

- Owner on the subscription.
- Entra ID role that can grant Microsoft Graph application permissions
  (Privileged Role Administrator or Global Administrator), needed for
  `Application.ReadWrite.OwnedBy`.
- Project Collection Administrator in your Azure DevOps organisation
  (organisation-level agent pool).
- A **PAT with a 1-day expiry** and only these scopes:
  - Agent Pools: Read & manage
  - Service Connections: Read, query & manage
  - Environment: Read & manage
  - Pipeline Resources: Use & manage
  - Build: Read
  - Project and Team: Read
  - Identity: Read
  - Code: Read (to clone this repository)

## Runbook

### 1. Prepare local shell (Bash)

```bash
az login

az account set --subscription "<subscription-id>"

# Your import of this repository: Repos -> movies-infra -> Clone
git clone "https://dev.azure.com/<organisation>/<project>/_git/movies-infra"
cd movies-infra/bootstrap

# Key for serial-console break-glass only: there is no inbound SSH.
ssh-keygen -t ed25519 -f ~/.ssh/movies-agent -N "" -C "movies-agent"

cp terraform.tfvars.example terraform.tfvars
# edit: subscription_id, admin_ssh_public_key (cat ~/.ssh/movies-agent.pub),
# approver_email, azdo_org_url, azdo_project_name
```

#### Create the PAT

If your organisation is not connected to Microsoft Entra ID (MSA-backed), it
does not accept Entra tokens and the PAT cannot be created with `az` or the
[PAT Lifecycle Management API](https://learn.microsoft.com/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate#manage-pats-with-the-lifecycle-management-apis).
Create it in the portal:

1. *User settings → Personal access tokens → + New Token*.
2. Name `movies-bootstrap`, organisation: yours (not *All accessible
   organizations*: global PATs stop working on 1 December 2026), expiry 1 day.
3. *Custom defined* scopes (click *Show all scopes* first), nothing else:
   - Agent Pools: **Read & manage**
   - Build: **Read** (reading approval checks back)
   - Code: **Read**
   - Environment: **Read & manage**
   - Identity: **Read**
   - Pipeline Resources: **Use & manage**
   - Project and Team: **Read**
   - Service Connections: **Read, query & manage**
4. Copy the token and paste it into the shell without echoing it
   (works in both Bash and zsh):

```bash
printf "Azure DevOps PAT: "; stty -echo; read -r TF_VAR_azdo_pat; stty echo; echo; export TF_VAR_azdo_pat
```

### 2. First apply (local state)

```bash
terraform init
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Cloud-init then installs the toolchain and registers the agent; it shows up as
**Online** in *Organization settings → Agent pools → movies-pool* after
roughly 5–10 minutes. Logs on the VM (via serial console):
`/var/log/agent-tools.log`, `/var/log/agent-register.log`.

### 3. Verify before closing anything

This is a gate. While the state is still local, the PAT is valid and nothing
is locked down, a fix is one more `terraform apply`. After steps 4–6 the same
fix needs the whole break-glass procedure.

**Online is not enough.** It proves only that registration worked; the
toolchain is installed by a separate cloud-init step that can fail on its own.

1. Agent pool `movies-pool`: agent `movies-agent-01` is **Online**.
2. The toolchain is complete. `install-tools.sh` ends its log with one
   `ok`/`MISSING` line per tool; read it (read-only, no inbound SSH needed):

   ```bash
   az vm run-command invoke -g rg-movies-mgmt -n vm-movies-agent \
     --command-id RunShellScript \
     --scripts 'sed -n "/>>> tool check/,\$p" /var/log/agent-tools.log' \
     --query "value[0].message" -o tsv
   ```

   Expected: `ok` for `az`, `terraform`, `node`, `npx`, `ansible`,
   `ansible-lint`, `checkov`, `tflint`, `gitleaks`, `sqlcmd`, `jq`, and no
   `Failed steps` line. Any `MISSING`: fix
   `templates/agent-cloud-init.yaml.tftpl` and replace the agent right now,
   still on local state (see [Replacing the agent](#replacing-the-agent)),
   then repeat this step. Never patch the VM by hand.
3. *Project settings → Service connections → sc-movies-azure*:
   **Verify and save** succeeds.
4. *Pipelines → Environments*: `movies-infra` and `movies-config` have an
   approval check.

Continue only when all four checks pass. Every pipeline also starts with a
preflight step that fails fast, with the list of missing tools, if the agent
is incomplete.

### 4. Move state into the storage account

```bash
terraform output -raw backend_hcl > ../backend.hcl
mv backend.tf.disabled backend.tf

# The data-plane role assignment can take a few minutes to propagate.
terraform init -migrate-state \
  -backend-config=../backend.hcl \
  -backend-config="key=bootstrap.tfstate"

rm -f terraform.tfstate terraform.tfstate.backup bootstrap.tfplan
```

Commit `backend.tf`, `../backend.hcl` and `.terraform.lock.hcl`.
Never commit `terraform.tfvars` (git-ignored).

### 5. Close the public door of the state account

```bash
SA=$(terraform output -raw tfstate_storage_account)
az storage account update -g rg-movies-mgmt -n "$SA" --public-network-access Disabled
```

Terraform deliberately ignores this attribute: the apply that disables public
access could no longer write its own state afterwards.

### 6. Revoke the PAT

*User settings → Personal access tokens → movies-bootstrap → Revoke*, then
`unset TF_VAR_azdo_pat`. The agent keeps working: registration exchanged the
PAT for the agent's own credentials.

## Changing bootstrap later (break-glass)

Bootstrap changes are rare and manual by design:

1. Re-enable public access on the state account (`--public-network-access Enabled`).
2. Create a new short-lived PAT as in [Create the PAT](#create-the-pat).
3. Initialise against the remote state, then plan and apply:

   ```bash
   terraform init -backend-config=../backend.hcl \
     -backend-config="key=bootstrap.tfstate"
   ```

4. Verify as in [step 3](#3-verify-before-closing-anything), still inside
   the window.
5. Only then disable public access again and revoke the PAT.

### Replacing the agent

The agent is immutable: cloud-init runs only on first boot, and
`custom_data` is in `ignore_changes` (so rotating the PAT never rebuilds a
working agent). To roll out a changed toolchain, replace the VM explicitly:
during the first run (step 3, local state, PAT still valid) or later within
the break-glass window above:

```bash
terraform plan -replace=azurerm_linux_virtual_machine.agent -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

The plan must show only the VM being replaced (1 to add, 1 to destroy). The
user-assigned identity is a separate resource, so the federated credential,
RBAC and the ABAC condition stay untouched; the new VM re-registers under the
same agent name (`--replace`). Then repeat
[step 3](#3-verify-before-closing-anything).

## Teardown

Destroy the stack first (pipeline), then:

```bash
az storage account update -g rg-movies-mgmt -n "$SA" --public-network-access Enabled
terraform state pull > terraform.tfstate     # keep a local copy
mv backend.tf backend.tf.disabled
terraform init -migrate-state                # back to local state
terraform destroy
```
