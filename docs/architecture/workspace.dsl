/*
 * C4 model of the Movies demo, as code (Structurizr DSL).
 *
 * One model, three views:
 *   Context     - level 1: people, our system, external systems (no technology)
 *   Containers  - level 2: deployable units and their protocols
 *   Deployment  - where every container runs: hub-spoke VNets, private endpoints
 *
 * Render locally:
 *   docker run -it --rm -p 8080:8080 -v "$PWD:/usr/local/structurizr" structurizr/lite
 * Validate in CI:
 *   structurizr-cli validate -workspace workspace.dsl
 */
workspace "Movies" "Demo project of the DevOps/DevSecOps Practices research club, Zhytomyr Polytechnic State University." {

    model {
        # --- People ------------------------------------------------------------
        viewer = person "Viewer" "Anonymous visitor who browses the catalog and watches films."
        admin  = person "Admin" "Club lead who signs in and adds films to the catalog."

        # --- External systems --------------------------------------------------
        entra       = softwareSystem "Microsoft Entra ID" "Admin sign-in (OIDC) and workload identities." "External"
        tmdb        = softwareSystem "TMDB API" "Film metadata, posters, trailer keys." "External"
        youtube     = softwareSystem "YouTube" "Embedded trailers." "External"
        letsencrypt = softwareSystem "Let's Encrypt" "Public TLS certificates (ACME)." "External"

        # --- Our system --------------------------------------------------------
        movies = softwareSystem "Movies" "Catalog of openly licensed films at movies.example.com." {
            proxy  = container "Reverse proxy" "Single entry point: TLS termination, routing, response cache for video ranges." "nginx"
            web    = container "Web app" "Server-rendered catalog, player and admin area." "Node.js, Express"
            worker = container "Worker" "Consumes image jobs and generates thumbnails." "Node.js"
            sql    = container "Catalog DB" "Films, genres, collections." "Azure SQL Database, Basic" "Database"
            blob   = container "Media storage" "Videos, posters, thumbnails." "Azure Blob Storage" "Storage"
            queue  = container "Job queue" "Image processing jobs." "Azure Queue Storage" "Queue"
            table  = container "Counters" "Views and likes." "Azure Table Storage" "Storage"
            kv     = container "Secrets" "TMDB key, Entra client secret, session secret." "Azure Key Vault" "Vault"
        }

        # --- Relationships (data flows; numbers match data-flows.md) -----------
        viewer -> proxy  "1. Browses and watches" "HTTPS 443"
        admin  -> proxy  "1. Manages the catalog" "HTTPS 443"
        admin  -> entra  "2. Signs in" "OIDC, HTTPS"
        viewer -> youtube "Plays trailers" "HTTPS, iframe"

        proxy  -> web    "3. Forwards requests" "HTTP :3000, localhost"
        proxy  -> letsencrypt "Renews certificate (certbot, DNS-01)" "ACME, HTTPS"

        web    -> sql    "5. Reads and writes the catalog" "TDS 1433 + TLS, private endpoint, managed identity"
        web    -> blob   "4. Streams video (Range), uploads posters" "HTTPS, private endpoint, managed identity"
        web    -> queue  "6. Enqueues image jobs" "HTTPS, private endpoint, managed identity"
        web    -> table  "Counts views and likes" "HTTPS, private endpoint, managed identity"
        web    -> kv     "7. Reads secrets" "HTTPS, private endpoint, managed identity"
        web    -> entra  "Completes sign-in" "OIDC, HTTPS"
        web    -> tmdb   "8. Fetches film metadata" "HTTPS, API key"

        worker -> queue  "6. Dequeues image jobs" "HTTPS, private endpoint, managed identity"
        worker -> blob   "Writes thumbnails" "HTTPS, private endpoint, managed identity"
        worker -> sql    "Updates film records" "TDS 1433 + TLS, private endpoint, managed identity"

        # --- Deployment --------------------------------------------------------
        demo = deploymentEnvironment "Demo" {

            azdo = deploymentNode "Azure DevOps" "Organisation / project with the three repositories" "SaaS" {
                pipelines = infrastructureNode "Azure Pipelines" "infra, configuration and app pipelines; approvals on environments" "Azure Pipelines"
            }

            cloudflare = deploymentNode "Cloudflare" "Authoritative DNS for example.com" "SaaS" {
                rootZone = infrastructureNode "example.com" "Delegates only 'movies' to Azure DNS (NS records)" "DNS zone"
            }

            azure = deploymentNode "Microsoft Azure" "Pay-As-You-Go subscription" "Sweden Central" {

                mgmt = deploymentNode "rg-movies-mgmt" "Management plane" "Resource group" {
                    hub = deploymentNode "vnet-movies-hub" "10.10.0.0/16" "Virtual network" {
                        agent = infrastructureNode "Build agent" "Self-hosted agent: Terraform, Ansible, Node; no inbound ports" "Ubuntu 24.04, Standard_B2pls_v2 (Arm64)"
                        tfstate = infrastructureNode "Terraform state" "Shared keys disabled, private endpoint only" "Azure Storage"
                    }
                }

                dns = deploymentNode "rg-movies-dns" "Shared DNS" "Resource group" {
                    privateDns = infrastructureNode "Private DNS zones" "privatelink.* zones linked to hub and spoke" "Azure Private DNS"
                }

                app = deploymentNode "rg-movies-app" "Workload" "Resource group" {
                    spoke = deploymentNode "vnet-movies-spoke" "10.20.0.0/16" "Virtual network" {
                        appVm = deploymentNode "vm-movies-app" "Inbound 443/80 from Internet, 22 from hub agents subnet only" "Ubuntu 24.04, Standard_B2pls_v2 (Arm64)" {
                            proxyInstance  = containerInstance proxy
                            webInstance    = containerInstance web
                            workerInstance = containerInstance worker
                        }
                        privateEndpoints = infrastructureNode "Private endpoints" "Blob, Queue, Table, SQL, Key Vault" "Azure Private Link"
                    }

                    sqlServer = deploymentNode "Azure SQL" "Entra-only authentication, public access disabled" "Azure SQL Database" {
                        sqlInstance = containerInstance sql
                    }
                    storage = deploymentNode "Storage account" "Public access disabled, managed identity only" "Azure Storage" {
                        blobInstance  = containerInstance blob
                        queueInstance = containerInstance queue
                        tableInstance = containerInstance table
                    }
                    keyVault = deploymentNode "Key Vault" "RBAC, public access disabled" "Azure Key Vault" {
                        kvInstance = containerInstance kv
                    }

                    publicDns  = infrastructureNode "movies.example.com" "A record of the app VM; TXT records for DNS-01" "Azure DNS"
                    monitoring = infrastructureNode "Monitoring" "Application Insights + Log Analytics (daily cap)" "Azure Monitor"
                    grafana    = infrastructureNode "Grafana" "Dashboards over Azure Monitor" "Azure Managed Grafana"
                }
            }

            # Deployment-level flows: the delivery path and the trust boundaries
            agent  -> pipelines "9a. Polls for jobs (outbound only)" "HTTPS 443, long polling"
            agent  -> tfstate   "Reads and writes state" "HTTPS, private endpoint, managed identity"
            agent  -> appVm     "9. Configures and deploys" "SSH over VNet peering"
            agent  -> privateDns "Resolves private endpoints" "DNS"
            appVm  -> privateEndpoints "Reaches PaaS data services" "Private Link"
            appVm  -> publicDns "Writes ACME TXT records" "Azure DNS API, managed identity"
            appVm  -> monitoring "Sends telemetry and logs" "HTTPS, Azure Monitor Agent"
            rootZone -> publicDns "Delegates subdomain" "NS"
            grafana -> monitoring "Queries" "HTTPS, managed identity"
        }
    }

    views {
        systemContext movies "Context" "Level 1: who uses Movies and what it depends on." {
            include *
            autoLayout lr
        }

        container movies "Containers" "Level 2: deployable units and protocols." {
            include *
            autoLayout lr
        }

        deployment movies demo "Deployment" "Hub-spoke deployment and trust boundaries in Azure." {
            include *
            autoLayout lr
        }

        styles {
            element "Person" {
                shape Person
                background #5b3fa8
                color #ffffff
            }
            element "Software System" {
                background #0f6e56
                color #ffffff
            }
            element "External" {
                background #8a8a85
                color #ffffff
            }
            element "Container" {
                background #1d9e75
                color #ffffff
            }
            element "Database" {
                shape Cylinder
            }
            element "Queue" {
                shape Pipe
            }
            element "Storage" {
                shape Folder
            }
            element "Vault" {
                shape Hexagon
            }
            element "Infrastructure Node" {
                background #ffffff
                color #2c2c2a
                stroke #5f5e5a
            }
        }
    }
}
