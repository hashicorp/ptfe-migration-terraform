data "aws_ami" "ubuntu" {
  owners = ["099720109477"] # Canonical

  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "cloud_config" {
  template = "${file("${path.module}/templates/cloud-config.yaml")}"

  vars {
    license_b64     = "${base64encode(file("${var.license_file}"))}"
    install_ptfe_sh = "${base64encode(file("${path.module}/files/install-ptfe.sh"))}"

    console_password = "${random_pet.console_password.id}"
    enc_password     = "${var.encryption_password != "" ? var.encryption_password : random_pet.enc_password.id}"

    proxy_url = "${var.proxy_url}"
    no_proxy  = "${var.no_proxy}"

    hostname = "${var.hostname}"

    pg_user         = "${var.db_username}"
    pg_password     = "${var.db_password}"
    pg_netloc       = "${var.db_endpoint}"
    pg_dbname       = "${var.db_database}"
    pg_extra_params = ""

    s3_bucket_name   = "${aws_s3_bucket.tfe_bucket.id}"
    s3_bucket_region = "${aws_s3_bucket.tfe_bucket.region}"
  }
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.cloud_config.rendered}"
  }
}

resource "aws_security_group" "ptfe" {
  vpc_id = "${var.vpc_id}"
  count  = "${length(var.internal_security_group_ids) != 0 ? 0 : 1}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8800
    to_port     = 8800
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # TCP All outbound traffic
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # UDP All outbound traffic
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "terraform-enterprise"
  }
}

resource "aws_security_group" "ptfe-external" {
  count  = "${length(var.external_security_group_ids) != 0 ? 0 : 1}"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8800
    to_port     = 8800
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # TCP All outbound traffic
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # UDP All outbound traffic
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "terraform-enterprise-external"
  }
}

resource "aws_launch_configuration" "ptfe" {
  image_id             = "${var.custom_ami != "" ? var.custom_ami : data.aws_ami.ubuntu.id}"
  instance_type        = "${var.instance_type}"
  key_name             = "${var.key_name}"
  security_groups      = ["${concat(var.internal_security_group_ids, aws_security_group.ptfe.*.id)}"]
  iam_instance_profile = "${aws_iam_instance_profile.tfe_instance.name}"

  user_data = "${data.template_cloudinit_config.config.rendered}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.volume_size}"
    delete_on_termination = true
  }
}

resource "aws_autoscaling_group" "ptfe" {
  # Interpolating the LC name into the ASG name here causes any changes that
  # would replace the LC (like, most commonly, an AMI ID update) to _also_
  # replace the ASG.
  name = "terraform-enterprise - ${aws_launch_configuration.ptfe.name}"

  launch_configuration  = "${aws_launch_configuration.ptfe.name}"
  desired_capacity      = 1
  min_size              = 1
  max_size              = 1
  vpc_zone_identifier   = ["${var.instance_subnet_id}"]
  load_balancers        = ["${aws_elb.ptfe.id}"]
  wait_for_elb_capacity = 1

  tag {
    key                 = "Name"
    value               = "terraform-enterprise-${var.hostname}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Hostname"
    value               = "${var.hostname}"
    propagate_at_launch = true
  }

  tag {
    key                 = "InstallationId"
    value               = "${var.installation_id}"
    propagate_at_launch = true
  }
}

resource "aws_elb" "ptfe" {
  internal        = "${var.internal_elb}"
  subnets         = ["${var.elb_subnet_id}"]
  security_groups = ["${concat(var.external_security_group_ids, aws_security_group.ptfe-external.*.id)}"]

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${var.cert_id}"
  }

  listener {
    instance_port     = 443
    instance_protocol = "https"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 8800
    instance_protocol  = "https"
    lb_port            = 8800
    lb_protocol        = "https"
    ssl_certificate_id = "${var.cert_id}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:443"
    interval            = 5
  }

  tags {
    Name = "terraform-enterprise"
  }
}

output "dns_name" {
  value = "${aws_elb.ptfe.dns_name}"
}

output "zone_id" {
  value = "${aws_elb.ptfe.zone_id}"
}

output "hostname" {
  value = "${var.hostname}"
}
