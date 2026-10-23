# App registration for admin sign-in (OIDC, authorization code flow).
# Created by the agent identity, which holds only Application.ReadWrite.OwnedBy:
# it can manage this app because it owns it, and no other app in the tenant.
#
# Single tenant. The app itself allows only var.admin_object_id and
# var.app_admin_object_ids into the admin area, so other tenant members can
# sign in but not administer.

resource "azuread_application" "movies" {
  display_name     = "Movies (${var.domain_name})"
  sign_in_audience = "AzureADMyOrg"
  owners           = [local.agent_principal_id]

  web {
    homepage_url  = "https://${var.domain_name}"
    redirect_uris = ["https://${var.domain_name}/auth/callback"]
    logout_url    = "https://${var.domain_name}/auth/signout"

    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }

  # Sign-in only: openid + profile + email from Microsoft Graph.
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1" # profile
      type = "Scope"
    }
    resource_access {
      id   = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" # email
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "movies" {
  client_id = azuread_application.movies.client_id
  owners    = [local.agent_principal_id]
}

resource "azuread_application_password" "movies" {
  application_id = azuread_application.movies.id
  display_name   = "terraform-managed"
  end_date       = var.secrets_expire_on
}
