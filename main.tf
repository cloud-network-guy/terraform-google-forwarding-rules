
locals {
  _forwarding_rules = [for i, v in var.lb_frontends :
    {
      create                 = coalesce(v.create, true)
      project_id             = coalesce(v.project_id, var.project_id)
      name                   = coalesce(v.name, "${var.name_prefix}-${i}")
      description            = coalesce(v.description, "Managed by Terraform")
      region                 = try(coalesce(v.region, var.region), null)
      ports                  = coalesce(v.ports, [])
      all_ports              = coalesce(v.all_ports, false)
      network                = coalesce(v.network, var.network, "default")
      subnet                 = v.subnet
      labels                 = { for k, v in coalesce(v.labels, {}) : k => lower(replace(v, " ", "_")) }
      is_psc                 = false # TODO
      ip_address             = v.ip_address
      address_name           = v.ip_address_name
      enable_ipv4            = coalesce(v.enable_ipv4, true)
      enable_ipv6            = coalesce(v.enable_ipv6, false)
      preserve_ip            = coalesce(v.preserve_ip, false)
      is_managed             = false # TODO
      is_mirroring_collector = false # TODO
      allow_global_access    = coalesce(v.allow_global_access, false)
      backend_service        = coalesce(v.backend_service_id, v.backend_service, v.backend_service_name)
      target                 = try(coalesce(v.target_id, v.target, v.target_name), null)
    } if v.create == true || coalesce(v.preserve_ip, false) == true
  ]
  __forwarding_rules = [for i, v in local._forwarding_rules :
    merge(v, {
      is_regional = try(coalesce(v.region, v.subnet), null) != null ? true : false
      is_internal = lookup(v, "subnet", null) != null ? true : false
      ip_protocol = length(v.ports) > 0 || v.all_ports ? "TCP" : "HTTP"
      target      = v.backend_service == null ? coalesce(v.target_id, v.target) : null
    })
  ]
  ___forwarding_rules = [for i, v in local.__forwarding_rules :
    merge(v, {
      network_tier = v.is_managed && !v.is_internal ? "STANDARD" : null
      subnetwork   = v.is_psc ? null : v.subnet
      all_ports    = v.is_psc || length(v.ports) > 0 ? false : v.all_ports
      port_range   = v.is_managed ? v.port_range : null
      target       = v.is_regional ? (contains(["TCP", "SSL"], v.ip_protocol) ? (v.is_psc ? v.target : null) : null) : null
      backend_service = startswith(v.backend_service, "projects/") ? v.backend_service : (
        "projects/${v.project_id}/${(v.is_regional ? "regions/${v.region}" : "global")}/backendServices/${v.backend_service}"
      )
    })
  ]
  ____forwarding_rules = [for i, v in local.___forwarding_rules :
    merge(v, {
      load_balancing_scheme = v.is_managed ? v.is_internal ? "INTERNAL_MANAGED" : (v.is_classic ? "EXTERNAL" : "EXTERNAL_MANAGED") : (v.is_internal ? "INTERNAL" : "EXTERNAL")
      allow_global_access   = v.is_internal ? v.allow_global_access : null
    })
  ]
  forwarding_rules = [for i, v in local.____forwarding_rules :
    merge(v, {
      load_balancing_scheme = v.is_psc ? "" : v.load_balancing_scheme
      index_key             = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
    }) if v.create == true
  ]
}

# Regional Forwarding rule
resource "google_compute_forwarding_rule" "default" {
  for_each               = { for i, v in local.forwarding_rules : v.index_key => v if v.is_regional }
  project                = each.value.project_id
  name                   = each.value.name
  port_range             = each.value.port_range
  ports                  = each.value.ports
  all_ports              = each.value.all_ports
  backend_service        = each.value.backend_service
  target                 = null
  ip_address             = each.value.ip_address
  load_balancing_scheme  = each.value.load_balancing_scheme
  ip_protocol            = each.value.ip_protocol
  labels                 = each.value.labels
  is_mirroring_collector = each.value.is_mirroring_collector
  network                = each.value.network
  region                 = each.value.region
  subnetwork             = each.value.subnetwork
  network_tier           = each.value.network_tier
  allow_global_access    = each.value.allow_global_access
  depends_on             = [google_compute_address.default]
}

# Global Forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  for_each              = { for i, v in local.forwarding_rules : v.index_key => v if !v.is_regional }
  project               = each.value.project_id
  name                  = each.value.name
  port_range            = each.value.port_range
  target                = each.value.target
  ip_address            = each.value.ip_address
  load_balancing_scheme = each.value.load_balancing_scheme
  ip_protocol           = each.value.ip_protocol
  labels                = each.value.labels
  depends_on            = [google_compute_global_address.default]
}


# Setup local for IP addresses
locals {
  _ip_addresses = [for i, v in local.forwarding_rules :
    merge(v, {
      name        = coalesce(v.address_name, v.name)
      ip_versions = v.is_internal || v.is_regional ? ["IPV4"] : concat(v.enable_ipv4 ? ["IPV4"] : [], v.enable_ipv6 ? ["IPV6"] : [])
    }) if v.create == true || v.preserve_ip == true
  ]
  ip_addresses = flatten([for i, v in local._ip_addresses :
    [for ip_version in v.ip_versions :
      {
        address_type              = v.is_internal ? "INTERNAL" : "EXTERNAL"
        name                      = v.name
        forwarding_rule_index_key = v.index_key
        is_regional               = v.is_regional
        region                    = v.is_regional ? v.region : "global"
        subnetwork                = v.subnetwork
        project_id                = v.project_id
        prefix_length             = v.is_regional ? 0 : null
        purpose                   = v.is_psc ? "GCE_ENDPOINT" : v.is_managed && v.is_internal ? "SHARED_LOADBALANCER_VIP" : null
        network_tier              = v.is_psc ? null : v.network_tier
        address                   = v.is_psc ? null : v.ip_address
        ip_version                = ip_version
        index_key                 = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : "${v.project_id}/${v.name}"
      } if v.create == true || coalesce(v.preserve_ip, false) == true
    ]
  ])
}

# Regional static IP
resource "google_compute_address" "default" {
  for_each      = { for i, v in local.ip_addresses : v.index_key => v if v.is_regional }
  project       = each.value.project_id
  name          = each.value.name
  address_type  = each.value.address_type
  ip_version    = each.value.ip_version
  address       = each.value.address
  region        = each.value.region
  subnetwork    = each.value.subnetwork
  network_tier  = each.value.network_tier
  purpose       = each.value.purpose
  prefix_length = each.value.prefix_length
}

# Global static IP
resource "google_compute_global_address" "default" {
  for_each     = { for i, v in local.ip_addresses : v.index_key => v if !v.is_regional }
  project      = each.value.project_id
  name         = each.value.name
  address_type = each.value.address_type
  ip_version   = each.value.ip_version
  address      = each.value.address
}
