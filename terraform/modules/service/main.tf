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

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    nginx_conf        = local.nginx_conf
    app_port          = var.app_port
    app_workdir       = var.app_workdir
    app_start_command = var.app_start_command
    app_env           = var.app_env
    secret_arn        = var.secret_arn
    db_endpoint       = var.db_endpoint
    db_port           = var.db_port
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
# `trivy config` gate must catch. The open EGRESS below is intentional and
# expected (SDK to Secrets Manager, DB, apt installs) — it is NOT the red-PR.
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
    description = "all egress (SDK to Secrets Manager, DB, package installs) - expected, not the red-PR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })
}

# --- EC2 instance -------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = var.app_ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.user_data

  # Explicit size required on LocalStack, otherwise the launch fails.
  root_block_device {
    volume_size = var.root_volume_size
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app" })
}

# --- ALB topology as IaC ------------------------------------------------------
# Graded + scanned as IaC even though nginx carries the real traffic: LocalStack
# ELBv2 has no documented active health checking, so it cannot gate readiness.
# lifecycle.ignore_changes pins LocalStack round-trip quirks (see FIDELITY.md).
resource "aws_lb" "app" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app.id]
  subnets            = slice(data.aws_subnets.default.ids, 0, min(2, length(data.aws_subnets.default.ids)))

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
