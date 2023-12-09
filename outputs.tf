
output "forwarding_rules" {
  value = [for i, v in local.forwarding_rules :
    {
      index_key = v.index_key
      name      = v.name
      region    = v.region
    }
  ]
}
