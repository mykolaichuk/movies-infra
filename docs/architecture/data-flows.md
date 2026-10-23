# Data flows

Numbers match the relationship labels in `workspace.dsl`.
Flows that carry secrets or privileged access (bold) are the first targets of
the threat model (STRIDE).

| # | Flow | Data | Category | Protocol / protection | Crosses boundary |
| --- | --- | --- | --- | --- | --- |
| 1 | Browser → nginx | page requests, session cookie | public / session token | HTTPS, TLS 1.2+ | **Internet → spoke** |
| **2** | Admin ↔ Entra ID | credentials, authorization code | **secrets, PII** | OIDC over HTTPS | **Internet → Entra ID** |
| 3 | nginx → Web app | proxied request | public | HTTP on localhost | no (same VM) |
| 4 | Web app → Blob (nginx caches the response) | video stream (Range) | public (CC BY / public domain) | HTTPS via private endpoint, managed identity | **VM → PaaS** |
| 5 | Web app → Azure SQL | catalog CRUD | internal | TDS 1433 + TLS via private endpoint, managed identity | **VM → PaaS** |
| 6 | Web app → Queue → Worker | film ID to process | internal | HTTPS via private endpoint, managed identity | **VM → PaaS** |
| **7** | Web app → Key Vault | TMDB key, client secret | **secrets** | HTTPS via private endpoint, managed identity | **VM → PaaS** |
| **8** | Web app → TMDB | API calls with key in header | **secret in transit** | HTTPS, outbound | **spoke → Internet** |
| **9** | Agent → app VM | Ansible runs, releases | **privileged access** | SSH over VNet peering | **hub → spoke** |
| 9a | Agent → Azure DevOps | job polling, logs | internal | HTTPS 443, outbound only | **hub → Internet** |
