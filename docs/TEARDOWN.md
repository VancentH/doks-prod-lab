# Teardown

`scripts/down.sh` removes every billable resource created by this lab,
keeping only the Spaces bucket (Terraform state, Velero backups) and the DNS
zone itself. Both are persistent, account-level resources created once by
hand, not by Terraform.

## What it does

1. Preflight checks (tools, environment variables)
2. Confirmation: you must type the cluster name to proceed
3. Stops Argo CD sync, so it doesn't recreate the Services this script deletes
4. Deletes objects that own resources outside the cluster: LoadBalancer
   Services, Gateways, and PVCs (which remove the backing DO Volume, since
   `reclaimPolicy=Delete`). Waits for DigitalOcean to actually release
   the Load Balancers and Volumes before continuing
5. Runs `terraform destroy`
6. Checks for leftover billable resources

## Destroy retries

DOKS deletes the cluster's Droplets asynchronously. If `terraform destroy`
tries to remove the shared VPC right after the cluster disappears, the
Droplets may not be gone yet and Terraform fails with *"Can not delete VPC
with members"*.

Rather than requiring a manual re-run, `down.sh` retries `terraform destroy`
up to `DESTROY_ATTEMPTS` times (default 4), waiting `DESTROY_RETRY_WAIT`
seconds (default 60) between attempts, until the VPC has no members left.

## Leftover checks

After destroy, the script checks for anything left behind: clusters,
Droplets, Load Balancers, Volumes, Snapshots, Reserved IPs, and two things
that are easy to miss because they aren't obviously "billed" per resource:

- **Firewalls** named `dpl-*` (Terraform-managed) or `k8s-*` (created by DOKS
  itself). The management Droplet's cloud firewall is a real resource this
  lab creates (see `terraform/modules/mgmt-k3s/main.tf`), so this check
  stays. It is not a leftover from an older setup.
- **DNS records** in the lab's zone other than `NS`/`SOA`. A record left
  pointing at a released IP is a dangling-DNS risk (subdomain takeover) if
  that IP gets reassigned to someone else's Droplet later.

A non-zero exit code means either `terraform destroy` didn't fully complete
or leftovers were found. Don't mistake that for a clean teardown.
