
locals {
  _forwarding_rules = [for i, v in var.lb_frontends :
    {
      create                 = coalesce(v.create, true)
      project_id             = coalesce(v.project_id, var.project_id)
      host_project_id        = try(coalesce(v.host_project_id, var.host_project_id), null)
      name                   = coalesce(v.name, "${var.name_prefix}-${i}")
      description            = coalesce(v.description, "Managed by Terraform")
      region                 = try(coalesce(v.region, var.region), null)
      ports                  = coalesce(v.ports, [])
      all_ports              = coalesce(v.all_ports, false)
      network                = coalesce(v.network, var.network, "default")
      subnet                 = v.subnet
      labels                 = { for k, v in coalesce(v.labels, {}) : k => lower(replace(v, " ", "_")) }
      ip_address             = v.ip_address
      address_name           = v.ip_address_name
      enable_ipv4            = coalesce(v.enable_ipv4, true)
      enable_ipv6            = coalesce(v.enable_ipv6, false)
      preserve_ip            = coalesce(v.preserve_ip, false)
      is_managed             = false # TODO
      is_mirroring_collector = false # TODO
      allow_global_access    = coalesce(v.allow_global_access, false)
      backend_service        = try(coalesce(v.backend_service_id, v.backend_service, v.backend_service_name), null)
      target                 = try(coalesce(v.target_id, v.target, v.target_name), null)
      psc                    = v.psc
    } if v.create == true || coalesce(v.preserve_ip, false) == true
  ]
  __forwarding_rules = [for i, v in local._forwarding_rules :
    merge(v, {
      is_regional = try(coalesce(v.region, v.subnet), null) != null ? true : false
      is_internal = lookup(v, "subnet", null) != null ? true : false
      ip_protocol = length(v.ports) > 0 || v.all_ports ? "TCP" : "HTTP"
      is_psc      = v.target_id != null || v.target != null ? true : false
      target      = v.backend_service == null ? v.target : null
      target_project_id = lookup(v, "target_project_id", v.project_id)
    })
  ]
  ___forwarding_rules = [for i, v in local.__forwarding_rules :
    merge(v, {
      network_tier = v.is_managed && !v.is_internal ? "STANDARD" : null
      subnetwork   = v.is_psc ? null : v.subnet
      all_ports    = v.is_psc || length(v.ports) > 0 ? false : v.all_ports
      port_range   = v.is_managed ? v.port_range : null
      #target       = v.is_regional ? (contains(["TCP", "SSL"], v.ip_protocol) ? (v.is_psc ? v.target : null) : null) : null
      target = v.target != null ? (startswith(v.target, "projects/") ? v.target : (
        "projects/${v.target_project_id}/${(v.is_regional ? "regions/${v.region}" : "global")}/backendServices/${v.target}"
      )) : null
      backend_service = v.backend_service != null ? (startswith(v.backend_service, "projects/") ? v.backend_service : (
        "projects/${v.project_id}/${(v.is_regional ? "regions/${v.region}" : "global")}/backendServices/${v.backend_service}"
      )) : null
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
    })
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
  target                 = each.value.target
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
    })
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



locals {
  nat_subnet_prefix = "https://www.googleapis.com/compute/v1/projects"
  _service_attachments = [for i, v in local.forwarding_rules :
    {
      is_regional               = v.is_regional
      project_id                = v.project_id
      name                      = coalesce(v.psc.name, v.name)
      description               = coalesce(v.psc.description, "PSC Publish for '${v.name}'")
      region                    = v.region
      reconcile_connections     = coalesce(v.psc.reconcile_connections, true)
      enable_proxy_protocol     = coalesce(v.psc.enable_proxy_protocol, false)
      auto_accept_all_projects  = coalesce(v.psc.auto_accept_all_projects, false)
      accept_project_ids        = coalesce(v.psc.accept_project_ids, [])
      consumer_reject_lists     = coalesce(v.psc.consumer_reject_lists, [])
      domain_names              = coalesce(v.psc.domain_names, [])
      host_project_id           = coalesce(v.psc.host_project_id, v.host_project_id, v.project_id)
      nat_subnets               = coalesce(v.psc.nat_subnets, [])
      forwarding_rule_index_key = v.index_key
    } if v.psc != null
  ]
  service_attachments = [for i, v in local._service_attachments :
    merge(v, {
      connection_preference = v.auto_accept_all_projects && length(v.accept_project_ids) == 0 ? "ACCEPT_AUTOMATIC" : "ACCEPT_MANUAL"
      nat_subnets = flatten([for nat_subnet in v.nat_subnets :
        [startswith("projects/", nat_subnet) ? nat_subnet : "${local.nat_subnet_prefix}/${v.host_project_id}/regions/${v.region}/subnetworks/${nat_subnet}"]
      ])
      accept_project_ids = [for p in v.accept_project_ids :
        {
          project_id       = p.project_id
          connection_limit = coalesce(p.connection_limit, 10)
        }
      ]
      target_service = try(google_compute_forwarding_rule.default[v.forwarding_rule_index_key].self_link, null)
      index_key      = v.is_regional ? "${v.project_id}/${v.region}/${v.name}" : null
    })
  ]
}

# Service Attachment (PSC Publish)
resource "google_compute_service_attachment" "default" {
  for_each              = { for k, v in local.service_attachments : v.index_key => v if v.is_regional }
  project               = each.value.project_id
  name                  = each.value.name
  region                = each.value.region
  description           = each.value.description
  enable_proxy_protocol = each.value.enable_proxy_protocol
  nat_subnets           = each.value.nat_subnets
  target_service        = each.value.target_service
  connection_preference = each.value.connection_preference
  dynamic "consumer_accept_lists" {
    for_each = each.value.accept_project_ids
    content {
      project_id_or_num = consumer_accept_lists.value.project_id
      connection_limit  = consumer_accept_lists.value.connection_limit
    }
  }
  consumer_reject_lists = each.value.consumer_reject_lists
  domain_names          = each.value.domain_names
  reconcile_connections = each.value.reconcile_connections
}
