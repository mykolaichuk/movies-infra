config {
  call_module_type = "local"
}

# Built-in Terraform language rules (unused declarations, typed variables,
# required providers, deprecated syntax, ...).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
