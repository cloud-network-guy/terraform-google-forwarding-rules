
output "forwarding_rules" {
  value = [for i, v in local.forwarding_rules :
    {
      index_key = v.index_key
      name      = v.name
      region    = v.is_regional ? v.region : "global"
      address   = v.is_regional ? google_compute_address.default[v.index_key].address : google_compute_global_address.default[v.index_key].address
    }
  ]
}
