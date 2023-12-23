# Client (consumer) connection to a GCP Service using Private Service Connect 

# Resources

- [google_compute_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address)
- [google_compute_global_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address)
- [google_compute_forwarding_rule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule)
- [google_compute_global_forwarding_rule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule)

---

# Inputs
 

| Name          | Description                                                  | Type     |
|---------------|--------------------------------------------------------------|----------|
| project\_id   | Project ID of the project to create the client connection in | `string` | 
| target\_id    | ID of Published PSC Service                                  | `string` |

`var.forwarding_rules` is a list of objects of forwarding rules to be created.  Attributes are described below.

| Name               | Description                                               | Type     | Default   |
|--------------------|-----------------------------------------------------------|----------|-----------|
| create             | Whether or not to create forwarding rule                  | `bool`   | true      |
| network\_name      | Name of the VPC network on the client side                | `string` | "default"  |
| region             | Name of the network this set of firewall rules applies to | `string` | n/a       |
| subnet\_name       | Name of the subnet to create the IP address on            | `string` | "default" |
| subnet\_id         | ID of the subnet to create the IP address on              | `string` | n/a       |
| name               | Explicit name for the PSC IP address and forwarding rule  | `string` | n/a       |
| description        | Description for the IP address                            | `string` | n/a       |
| network\_project\_id | If using Shared VPC, the host project ID for the network  | `string` | n/a       |
| target\_project\_id | Project ID of Published PSC Service                       | `string` | n/a       |
| target\_name       | Name of Published PSC Service                             | `string` | n/a       |
| target\_region     | Region of Published PSC Service                           | `string` | n/a       |

#### Notes

- Either `target_id` or `target_name` must be provided
- If neither `target_id` nor `target_project_id` are provided, target project ID is assumed same as `var.project_id`
- If neither `target_id` nor `target_region` are provided, target region is assumed same as `var.region`
- If `var.region` is not specified, it is assumed to be same as Publisher
- If name is not specified, it will be auto-generated: `psc-endpoint-${REGION}-${SERVICE_NAME}`
- If description is not provided, it will be the target service ID

## Outputs

`forwarding_rules` returns a list of forwarding rules managed by this module.  Attributes are described below.

| Name    | Description                           | Type     |
|---------|---------------------------------------|----------|
| name    | The name of the Forwarding Rule       | `string` |
| address | The IP Address of the Forwarding Rule | `string` |


### Examples

#### Basic Example with custom subnet name and PSC Service ID

```
project_id        = "my-project-id"
network_name      = "my-network-name"
subnet_name       = "my-subnet-name"
region            = "us-east4"
target_id         = "projects/another-project-id/regions/us-east4/serviceAttachments/service-name"
```

#### When local Network uses Shared VPC

```
project_id          = "my-project-id"
network_project_id  = "my-shared-vpc-host-project-id"
network_name        = "my-network-name"
subnet_name         = "my-subnet-name"
region              = "us-west2"
target_id           = "projects/another-project-id/regions/us-west2/serviceAttachments/service-name"
```

#### Auto-Generated Target Service ID

```
project_id        = "my-project-id"
network_name      = "my-network-name"
subnet_name       = "my-subnet-name"
region            = "us-east4"
target_project_id = "my-buddys-project"
target_name       = "my-buddys-service"
target_region     = "us-east4"
```
