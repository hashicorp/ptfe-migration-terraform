### =================================================================== REQUIRED

variable "license_file" {
  type        = "string"
  description = "path to Replicated license file"
}

variable "db_username" {
  type        = "string"
  description = "username to connect to PostgreSQL database"
}

variable "db_password" {
  type        = "string"
  description = "password for above username"
}

variable "db_endpoint" {
  type        = "string"
  description = "hostname of PostgreSQL"
}

variable "db_database" {
  type        = "string"
  description = "database within PostgreSQL"
}

### =================================================================== OPTIONAL

variable "installation_id" {
  description = "unique identifier to apply to resources created"
  type        = "string"
  default     = "ptfe"
}

variable "encryption_password" {
  description = "Password used to encrypt sensitive data at rest"
  type        = "string"
  default     = ""
}

variable "region" {
  description = "aws region where resources will be created"
  type        = "string"
  default     = "us-west-2"
}

variable "cidr" {
  description = "cidr block for vpc"
  type        = "string"
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "ec2 instance type"
  type        = "string"
  default     = "m4.xlarge"
}

variable "volume_size" {
  description = "size of the root volume in gb"
  type        = "string"
  default     = "40"
}

variable "custom_ami" {
  description = "AMI to launch instance with; defaults to latest Ubuntu Xenial"
  type        = "string"
  default     = ""
}

variable "release_number" {
  description = "The sequence number of the release to install"
  type        = "string"
  default     = ""
}

### ======================================================================= MISC

## random password for the replicated console
resource "random_pet" "console_password" {
  length = 3
}

resource "random_pet" "enc_password" {
  length = 3
}

variable "hostname" {}

variable "vpc_id" {}

variable "cert_id" {}

// Used for the ELB
variable "instance_subnet_id" {}

// Used for the instance
variable "elb_subnet_id" {}

variable "key_name" {}

variable "kms_key_id" {}

variable "arn_partition" {
  description = "AWS partition to use (used mostly by govcloud)"
  default     = "aws"
}

variable "internal_elb" {
  default = false
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
  type        = "string"
  default     = ""
}

variable "no_proxy" {
  description = "hosts to exclude from proxying (only applies when proxy_url is set)"
  type        = "string"
  default     = ""
}
