# DigitalOcean API Token Scopes

When creating the Personal Access Token used for `DIGITALOCEAN_TOKEN`, grant the following resource scopes so that Terraform provisioning/destroy and the `scripts/down.sh` checks work correctly.

| Resource | Permissions | Used for |
| --- | --- | --- |
| account | read | `doctl account get` (down.sh preflight check) |
| kubernetes | create, read, update, delete, access cluster | DOKS cluster and kubeconfig |
| droplet | create, read, update, delete | Managing the cluster's k3s Droplets |
| vpc | create, read, update, delete | Cluster networking |
| load_balancer | read, delete | down.sh check and cleanup |
| block_storage | read, delete | down.sh check and cleanup (Volumes) |
| ssh_key | read, create | Cluster Droplet login |
| tag | create, read | Terraform resource tagging |
| domain | create, read, update, delete | DNS (Part 1 domain setup) |
| snapshot, reserved_ip | read | down.sh leftover-resource check |
| project | create, read, update, delete | — |
