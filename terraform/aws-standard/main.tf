terraform {
  required_version = ">= 0.9.3"
}

variable "fqdn" {
  description = "The fully qualified domain name the cluster is accessible as"
}

variable "hostname" {
  description = "The name the cluster will be register as under the zone (optional if separately managing DNS)"
  default     = ""
}

variable "zone_id" {
  description = "The route53 zone id to register the hostname in (optional if separately managing DNS)"
  default     = ""
}

variable "cert_id" {
  description = "CMS certificate ID to use for TLS attached to the ELB"
}

variable "instance_subnet_id" {
  description = "Subnet to place the instance into"
}

variable "elb_subnet_id" {
  description = "Subnet that will hold the ELB"
}

variable "data_subnet_ids" {
  description = "Subnets to place the data services (RDS) into (2 required for availability)"
  type        = "list"
}

variable "db_password" {
  description = "RDS password to use"
}

variable "bucket_name" {
  description = "S3 bucket to store artifacts into"
}

variable "manage_bucket" {
  description = "Indicate if the S3 bucket should be created/owned by this terraform state"
  default     = true
}

variable "key_name" {
  description = "Keypair name to use when started the instances, leave blank for no SSH access"
  default     = ""
}

variable "db_username" {
  description = "RDS username to use"
  default     = "atlas"
}

variable "region" {
  description = "AWS region to place cluster into"
}

variable "instance_type" {
  description = "AWS instance type to use"
  default     = "m4.2xlarge"
}

variable "release_number" {
  description = "The sequence number of the release to install"
  default     = ""
}

data "aws_subnet" "instance" {
  id = "${var.instance_subnet_id}"
}

data "aws_vpc" "vpc" {
  id = "${data.aws_subnet.instance.vpc_id}"
}

variable "db_size_gb" {
  description = "Disk size of the RDS instance to create"
  default     = "80"
}

variable "db_instance_class" {
  default = "db.m4.large"
}

variable "db_name" {
  description = "Name of the Postgres database. Set this blank on the first run if you are restoring using a snapshot_identifier. Subsequent runs should let it take its default value."
  default     = "atlas_production"
}

// Multi AZ allows database snapshots to be taken without incurring an I/O
// penalty on the  primary node. This should be `true` for production workloads.
variable "db_multi_az" {
  description = "Multi-AZ sets up a second database instance for perforance and availability"
  default     = true
}

variable "db_snapshot_identifier" {
  description = "Snapshot of database to use upon creation of RDS"
  default     = ""
}

variable "bucket_force_destroy" {
  description = "Control if terraform should destroy the S3 bucket even if there are contents. This wil destroy any backups."
  default     = false
}

variable "kms_key_id" {
  description = "A KMS Key to use rather than having a new one created"
  default     = ""
}

variable "arn_partition" {
  description = "AWS partition to use (used mostly by govcloud)"
  default     = "aws"
}

variable "internal_elb" {
  description = "Indicates that this installation is to be accessed only by a private subnet"
  default     = false
}

variable "external_security_group_ids" {
  description = "The IDs of existing security groups to use for the ELB instead of creating one."
  type        = "list"
  default     = []
}

variable "internal_security_group_ids" {
  description = "The IDs of existing security groups to use for the instance instead of creating one."
  type        = "list"
  default     = []
}

variable "proxy_url" {
  description = "A url (http or https, with port) to proxy all external http/https request from the cluster to."
  default     = ""
}

variable "no_proxy" {
  type        = "string"
  description = "hosts to exclude from proxying (only applies when proxy_url is set)"
  default     = ""
}

variable "custom_ami" {
  type        = "string"
  description = "AMI to install software into, defaults to Ubuntu 16.04"
  default     = ""
}

variable "volume_size" {
  description = "size of the root volume in gb"
  type        = "string"
  default     = "40"
}

variable "license_file" {
  type        = "string"
  description = "path to Replicated license to use"
}

variable "encryption_password" {
  type        = "string"
  description = "password to use to encrypt data, output by migration tool"
}

# A random identifier to use as a suffix on resource names to prevent
# collisions when multiple instances of TFE are installed in a single AWS
# account.
resource "random_id" "installation-id" {
  byte_length = 6
}

provider "aws" {
  region = "${var.region}"
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = "${data.aws_caller_identity.current.account_id}"
}

resource "aws_kms_key" "key" {
  count       = "${var.kms_key_id != "" ? 0 : 1}"
  description = "TFE resource encryption key"

  tags {
    Name = "terraform_enterprise-${random_id.installation-id.hex}"
  }

  # This references the role created by the instance module as a name
  # rather than a resource attribute because it causes too much churn.
  # So if the name is changed in the instance module, you need to change
  # the name here too.
  policy = <<-JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Allow KMS for TFE creator",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "${data.aws_caller_identity.current.arn}",
          "arn:${var.arn_partition}:iam::${data.aws_caller_identity.current.account_id}:root",
          "arn:${var.arn_partition}:iam::${data.aws_caller_identity.current.account_id}:role/tfe_iam_role-${random_id.installation-id.hex}"
        ]
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
  JSON
}

resource "aws_kms_alias" "key" {
  name          = "alias/terraform_enterprise-${random_id.installation-id.hex}"
  target_key_id = "${coalesce(var.kms_key_id, join("", aws_kms_key.key.*.key_id))}"
}

module "route53" {
  source         = "../modules/tfe-route53"
  hostname       = "${var.hostname}"
  zone_id        = "${var.zone_id}"
  alias_dns_name = "${module.instance.dns_name}"
  alias_zone_id  = "${module.instance.zone_id}"
}

module "instance" {
  source                      = "../modules/installer"
  installation_id             = "${random_id.installation-id.hex}"
  instance_type               = "${var.instance_type}"
  hostname                    = "${var.fqdn}"
  vpc_id                      = "${data.aws_subnet.instance.vpc_id}"
  cert_id                     = "${var.cert_id}"
  instance_subnet_id          = "${var.instance_subnet_id}"
  elb_subnet_id               = "${var.elb_subnet_id}"
  key_name                    = "${var.key_name}"
  db_username                 = "${var.db_username}"
  db_password                 = "${var.db_password}"
  db_endpoint                 = "${module.db.endpoint}"
  db_database                 = "${module.db.database}"
  bucket_name                 = "${var.bucket_name}"
  bucket_region               = "${var.region}"
  kms_key_id                  = "${coalesce(var.kms_key_id, join("", aws_kms_key.key.*.arn))}"
  bucket_force_destroy        = "${var.bucket_force_destroy}"
  manage_bucket               = "${var.manage_bucket}"
  arn_partition               = "${var.arn_partition}"
  internal_elb                = "${var.internal_elb}"
  external_security_group_ids = "${var.external_security_group_ids}"
  internal_security_group_ids = "${var.internal_security_group_ids}"
  proxy_url                   = "${var.proxy_url}"
  no_proxy                    = "${var.no_proxy}"
  custom_ami                  = "${var.custom_ami}"
  volume_size                 = "${var.volume_size}"
  license_file                = "${var.license_file}"
  encryption_password         = "${var.encryption_password}"
  release_number              = "${var.release_number}"
}

module "db" {
  source                  = "../modules/rds"
  instance_class          = "${var.db_instance_class}"
  multi_az                = "${var.db_multi_az}"
  name                    = "tfe-${random_id.installation-id.hex}"
  username                = "${var.db_username}"
  password                = "${var.db_password}"
  storage_gbs             = "${var.db_size_gb}"
  subnet_ids              = "${var.data_subnet_ids}"
  engine_version          = "9.4"
  vpc_cidr                = "${data.aws_vpc.vpc.cidr_block}"
  vpc_id                  = "${data.aws_subnet.instance.vpc_id}"
  backup_retention_period = "31"
  storage_type            = "gp2"
  kms_key_id              = "${coalesce(var.kms_key_id, join("", aws_kms_key.key.*.arn))}"
  snapshot_identifier     = "${var.db_snapshot_identifier}"
  db_name                 = "${var.db_name}"
}

output "kms_key_id" {
  value = "${coalesce(var.kms_key_id, join("", aws_kms_key.key.*.arn))}"
}

output "url" {
  value = "https://${var.fqdn}"
}

output "dns_name" {
  value = "${module.instance.dns_name}"
}

output "zone_id" {
  value = "${module.instance.zone_id}"
}

output "iam_role" {
  value = "${module.instance.iam_role}"
}

output "replicated_console_password" {
  value = "${module.instance.replicated_console_password}"
}

output "encryption_password" {
  value = "${module.instance.encryption_password}"
}
