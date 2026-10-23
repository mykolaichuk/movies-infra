# Single points of failure

The demo is deliberately **not** highly available. Each SPOF below is a
conscious cost decision, written down so it can be defended and reversed.

| SPOF | Why accepted in the demo | Production fix |
| --- | --- | --- |
| One app VM | cost | VM Scale Set or 2 VMs behind Load Balancer / Application Gateway, across availability zones |
| One build agent | not on the runtime path | 2+ agents in the pool, or Managed DevOps Pools |
| Azure SQL Basic (5 DTU), no replica | fixed ~5 USD/month | zone-redundant database, geo-replica, failover group |
| Storage accounts LRS | cost | ZRS / GZRS |
| TLS certificate lives on the VM | simplicity | Application Gateway / Front Door with managed certificates |
| One region (Sweden Central) | scope | paired region + traffic manager / Front Door |

## Deliberate simplifications

| Simplification | Next step for a real project |
| --- | --- |
| One environment (no dev/prod split) | Separate dev and prod resource groups, state files, agent identities and service connections; build once, deploy to dev, approve, promote the same artifact to prod |
| Raw `azurerm_*` resources | Azure Verified Modules (AVM) for the workload layer once they support the provider version in use |
