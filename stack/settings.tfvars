# Non-secret settings of the stack, committed on purpose.
# Secrets never go here. Third-party secrets: pipelines/set-secret.yml -> Key Vault.
# Replace every value below before the first run of the infra pipeline.

# Public host name of the app. You need a DNS zone you control (the parent,
# e.g. example.com) to delegate this name to Azure DNS with NS records.
domain_name = "movies.example.com"

# Your own Entra ID object ID: az ad signed-in-user show --query id -o tsv
admin_object_id = "00000000-0000-0000-0000-000000000000"

# Further admins of the movies app (/admin only, no Azure roles).
# Entra admin center -> Users -> <user> -> Object ID.
app_admin_object_ids = []
