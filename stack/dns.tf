# Public zone for the delegated subdomain (var.domain_name). The parent zone
# stays with its own DNS provider (e.g. Cloudflare), which only holds 4 NS
# records pointing here (output: dns_name_servers).

resource "azurerm_dns_zone" "public" {
  name                = var.domain_name
  resource_group_name = local.rg
  tags                = local.tags
}

resource "azurerm_dns_a_record" "apex" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = local.rg
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.app.id # alias: follows the IP automatically
  tags                = local.tags
}

# Only Let's Encrypt may issue certificates for this name.
resource "azurerm_dns_caa_record" "apex" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = local.rg
  ttl                 = 3600
  tags                = local.tags

  record {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org"
  }

  record {
    flags = 0
    tag   = "issuewild"
    value = ";"
  }
}
