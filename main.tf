# Redthread read-only scan access, as an Oracle Resource Manager stack.
# Creates one user in one group holding read-only policy, uploads the workspace's PUBLIC key to it, then
# tells Redthread the new user's OCID. Destroy this stack (or delete the user's API key) to revoke.
terraform {
  required_version = ">= 1.2"
  required_providers {
    oci  = { source = "oracle/oci" }
    http = { source = "hashicorp/http", version = ">= 3.4.0" }
  }
}

variable "tenancy_ocid" {}
variable "region" {}
variable "public_key_b64" {
  description = "The workspace's public key (base64 body, no PEM header). Filled in by the link."
}
variable "scan_user_email" {
  description = "Primary email for the scan user (required by identity domains; it can never sign in)."
  default     = "cloud-scan@redthreadsec.com"
}
variable "connect_url" {
  description = "Where to report the new user's OCID. Filled in by the link."
}

provider "oci" {
  region = var.region
}

# IAM writes must go to the home region, wherever the stack runs.
data "oci_identity_region_subscriptions" "home" {
  tenancy_id = var.tenancy_ocid
  filter {
    name   = "is_home_region"
    values = [true]
  }
}

locals {
  home_region = data.oci_identity_region_subscriptions.home.region_subscriptions[0].region_name
  public_key  = "-----BEGIN PUBLIC KEY-----\n${join("\n", regexall(".{1,64}", var.public_key_b64))}\n-----END PUBLIC KEY-----\n"
}

provider "oci" {
  alias  = "home"
  region = local.home_region
}

resource "oci_identity_group" "scan" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "RedthreadCloudScan"
  description    = "Redthread read-only cloud scan"
}

resource "oci_identity_user" "scan" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "redthread-cloud-scan"
  description    = "Redthread read-only cloud scan (API key only)"
  email          = var.scan_user_email
}

# API key only: no console password, auth tokens, SMTP or S3-compatible keys.
resource "oci_identity_user_capabilities_management" "scan" {
  provider                     = oci.home
  user_id                      = oci_identity_user.scan.id
  can_use_api_keys             = true
  can_use_auth_tokens          = false
  can_use_console_password     = false
  can_use_customer_secret_keys = false
  can_use_smtp_credentials     = false
}

resource "oci_identity_user_group_membership" "scan" {
  provider = oci.home
  group_id = oci_identity_group.scan.id
  user_id  = oci_identity_user.scan.id
}

resource "oci_identity_policy" "scan" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "RedthreadCloudScan"
  description    = "Read-only posture scan by Redthread"
  statements = [
    "Allow group RedthreadCloudScan to inspect all-resources in tenancy",
    "Allow group RedthreadCloudScan to read buckets in tenancy",
    "Allow group RedthreadCloudScan to read virtual-network-family in tenancy",
    "Allow group RedthreadCloudScan to read users in tenancy",
  ]
}

resource "oci_identity_api_key" "scan" {
  provider  = oci.home
  user_id   = oci_identity_user.scan.id
  key_value = local.public_key
}

# Report back only once everything exists. Redthread verifies with a signed read before it stores
# anything, so a stray or forged report connects nothing.
data "http" "connect" {
  url             = var.connect_url
  method          = "POST"
  request_headers = { "Content-Type" = "application/json" }
  request_body = jsonencode({
    tenancy_ocid = var.tenancy_ocid
    user_ocid    = oci_identity_user.scan.id
    region       = local.home_region
  })
  depends_on = [oci_identity_api_key.scan, oci_identity_policy.scan, oci_identity_user_group_membership.scan]
}

output "result" {
  value = data.http.connect.status_code == 202 ? "Done - return to Redthread, it connects by itself." : "Redthread did not accept the connection (HTTP ${data.http.connect.status_code}): ${data.http.connect.response_body}"
}
