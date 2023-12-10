variable "project_id" {
  description = "GCP Project ID to create resources in"
  type        = string
}
variable "host_project_id" {
  description = "If using Shared VPC, the GCP Project ID for the host network"
  type        = string
  default     = null
}
variable "region" {
  description = "GCP region name for the IP address and forwarding rule"
  type        = string
  default     = null
}
variable "network" {
  type    = string
  default = null
}
variable "name_prefix" {
  type    = string
  default = "fe"
}
variable "lb_frontends" {
  description = "List of Load Balancer Frontends"
  type = list(object({
    create                     = optional(bool, true)
    project_id                 = optional(string)
    host_project_id            = optional(string)
    region                     = optional(string)
    name                       = optional(string)
    description                = optional(string)
    network                    = optional(string)
    subnet                     = optional(string)
    backend_service            = optional(string)
    backend_service_id         = optional(string)
    backend_service_project_id = optional(string)
    backend_service_region     = optional(string)
    backend_service_name       = optional(string)
    target                     = optional(string)
    target_id                  = optional(string)
    target_project_id          = optional(string)
    target_region              = optional(string)
    target_name                = optional(string)
    allow_global_access        = optional(string)
    enable_ipv4                = optional(bool)
    enable_ipv6                = optional(bool)
    ip_address                 = optional(string)
    ip_address_name            = optional(string)
    preserve_ip                = optional(bool)
    ports                      = optional(list(number))
    all_ports                  = optional(bool)
    labels                     = optional(map(string))
    psc = optional(object({
      create                   = optional(bool, false)
      project_id               = optional(string)
      host_project_id          = optional(string)
      description              = optional(string)
      forwarding_rule_name     = optional(string)
      target_service_id        = optional(string)
      nat_subnets              = optional(list(string))
      enable_proxy_protocol    = optional(bool)
      auto_accept_all_projects = optional(bool)
      accept_project_ids = optional(list(object({
        project_id       = string
        connection_limit = optional(number)
      })))
      domain_names          = optional(list(string))
      consumer_reject_lists = optional(list(string))
      reconcile_connections = optional(bool)
    }))
  }))
  default = []
}
