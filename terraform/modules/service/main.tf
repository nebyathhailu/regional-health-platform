# =============================================================================
# modules/service — EC2 (Docker-backed) + nginx + SG + ALB-as-IaC
#
# The instance boots the app image (tagged as an AMI by CI). user-data installs
# nginx, renders a readiness-gated reverse proxy, and starts the app — passing
# the secret ARN + DB endpoint but NEVER the secret value. The app resolves its
# DB credentials from Secrets Manager at boot.
#
# FIDELITY (LocalStack): only the default SG is honoured and ingress rules apply
# only at instance creation — see README.md and FIDELITY.md.
# =============================================================================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  # Scope ingress to the VPC CIDR unless the caller overrides. Never 0.0.0.0/0.
  ingress_cidrs = var.ingress_cidrs != null ? var.ingress_cidrs : [data.aws_vpc.default.cidr_block]

  # CI tags the Docker-backed EC2 AMI as `localstack-ec2/<name>:ami-<hex>`
  # (see variables.tf's validation, which accepts either that form or a bare
  # id). AWS's DescribeImages only accepts the bare `ami-<hex>` id -- passing
  # the full tag straight through fails with InvalidAMIID.Malformed
  # (confirmed in CI: "localstack-ec2/capacity-api:ami-cb5f14a15bcf" rejected,
  # "expecting ami-..."). Strip everything through the last colon; a value
  # that's already a bare ami-id (no colon) passes through unchanged.
  app_ami_id = element(split(":", var.app_ami_id), length(split(":", var.app_ami_id)) - 1)

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    nginx_conf        = local.nginx_conf
    app_port          = var.app_port
    app_workdir       = var.app_workdir
    app_start_command = var.app_start_command
    app_env           = var.app_env
    secret_arn        = var.secret_arn
    db_endpoint       = var.db_endpoint
    db_port           = var.db_port
    db_ca_cert        = var.db_ca_cert
    aws_endpoint_url  = var.aws_endpoint_url
    aws_region        = var.aws_region
  })

  nginx_conf = templatefile("${path.module}/templates/nginx.conf.tftpl", {
    app_port = var.app_port
  })
}

# --- Security group -----------------------------------------------------------
# Only port 80 (nginx) is exposed. The app port is deliberately NOT opened: nginx
# reaches the app over loopback (127.0.0.1:app_port) inside the instance, which no
# ingress rule governs. Opening app_port would grant an ungated path straight to
# business traffic, bypassing the readiness gate and defeating C4.
#
# INGRESS scoping (see local.ingress_cidrs) is what the trivy red-PR targets:
# flipping the port-80 ingress to 0.0.0.0/0 is the deliberate insecure change the
# `trivy config` gate must catch.
#
# EGRESS is scoped to the ports the instance genuinely needs to reach the public
# internet: apt (80/443), DNS (53), and the managed MySQL at Aiven (a public host
# on db_port). The CIDR must stay /0 because those destinations are public and
# dynamic (apt mirrors, Aiven's rotating IPs), so AWS-0104 is suppressed with
# justification rather than falsely narrowed. This is NOT the red-PR (that's ingress).
#trivy:ignore:AVD-AWS-0104 public egress required (apt, DNS, Aiven MySQL); scoped to needed ports, dynamic public IPs
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "nginx (80) for the ${var.name_prefix} instance; app port is loopback-only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "nginx HTTP (the only external path; enforces the readiness gate)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.ingress_cidrs
  }

  egress {
    description = "HTTPS out (AWS SDK, apt-https, Aiven TLS control)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP out (apt package mirrors)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "managed MySQL at Aiven (public host on db_port)"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })
}

# --- EC2 instance -------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = local.app_ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.user_data

  # Require IMDSv2 session tokens (AWS-0028). FIDELITY: LocalStack's IMDS is
  # limited (no iam/security-credentials/ path), so this can't be exercised at
  # runtime here — but it's the correct posture for the real-AWS transfer.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Explicit size required on LocalStack, otherwise the launch fails.
  # encrypted = true satisfies AWS-0131. FIDELITY: like RDS storage_encrypted,
  # LocalStack echoes this back as configured but applies no real encryption.
  root_block_device {
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app" })
}

# --- ALB topology as IaC ------------------------------------------------------
# Graded + scanned as IaC even though nginx carries the real traffic: LocalStack
# ELBv2 has no documented active health checking, so it cannot gate readiness.
# lifecycle.ignore_changes pins LocalStack round-trip quirks (see FIDELITY.md).
# internal = false is intentional: an ALB fronting a public service must be
# internet-facing, so AWS-0053 is suppressed by design (not a defect).
#trivy:ignore:AVD-AWS-0053 internet-facing is the intended design for a public entrypoint
resource "aws_lb" "app" {
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.app.id]
  subnets                    = slice(data.aws_subnets.default.ids, 0, min(2, length(data.aws_subnets.default.ids)))
  drop_invalid_header_fields = true # AWS-0052

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "app" {
  name = "${var.name_prefix}-tg"
  # Target nginx (80), not the app port directly, so the declared LB path also
  # goes through the readiness gate — consistent with the SG (no app-port ingress).
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path                = "/readyz"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg" })
}

# HTTP (not HTTPS) is accepted for this lab: the ALB is declared as IaC only and
# does not route traffic on LocalStack (ELBv2 health checking is undocumented),
# and there is no TLS material anywhere in the lab — nginx on the instance
# terminates the only real traffic, over HTTP. Production would add an ACM cert,
# an HTTPS (443) listener, and redirect this one to it. AWS-0054 suppressed with
# that justification; noted in evidence/05-gates/README.md.
#trivy:ignore:AVD-AWS-0054 ALB is non-routing IaC only; no TLS material in lab; nginx terminates real traffic
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  lifecycle {
    # LocalStack round-trips the listener port oddly; pin it so plan stays empty.
    ignore_changes = [port]
  }
}
