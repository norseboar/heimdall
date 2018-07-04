provider "aws" {
  version = "1.14.1"
  region  = "us-east-1"
}

terraform {
  required_version = ">= 0.11.7"
}

locals {
  app_port = 8080
}

data "aws_caller_identity" "current" {}

## IAM

resource "aws_iam_role" "execution-role" {
  name_prefix = "heimdall-execution-"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "execution-attach" {
  role       = "${aws_iam_role.execution-role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task-role" {
  name_prefix = "heimdall-task-"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      }
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "task-policy" {
  name_prefix = "heimdall-task-"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ssm:GetParameters"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/heimdall/*"
      ]
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "task-attach" {
  role       = "${aws_iam_role.task-role.name}"
  policy_arn = "${aws_iam_policy.task-policy.arn}"
}

## Networking

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "heimdall-vpc"
  cidr = "172.21.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = []
  public_subnets  = ["172.21.0.0/24", "172.21.1.0/24", "172.21.2.0/24"]

  enable_nat_gateway = false

  tags = {
    Terraform = "true"
    Config    = "heimdall"
  }
}

resource "aws_network_acl" "public" {
  vpc_id     = "${module.vpc.vpc_id}"
  subnet_ids = ["${module.vpc.public_subnets}"]

  tags = {
    Name = "heimdall-public"
  }
}

resource "aws_network_acl_rule" "public_ingress" {
  network_acl_id = "${aws_network_acl.public.id}"
  rule_number    = "100"
  egress         = false
  cidr_block     = "0.0.0.0/0"
  protocol       = "all"
  rule_action    = "allow"
}

resource "aws_network_acl_rule" "public_egress" {
  network_acl_id = "${aws_network_acl.public.id}"
  rule_number    = "100"
  egress         = true
  cidr_block     = "0.0.0.0/0"
  protocol       = "all"
  rule_action    = "allow"
}

resource "aws_security_group" "lb" {
  name_prefix = "heimdall-lb-"
  description = "Controls access to the ALB"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name_prefix = "heimdall-app-"
  description = "Controls access to the app"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    protocol        = "-1"
    from_port       = 0
    to_port         = 0
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## ALB

resource "aws_alb" "main" {
  name_prefix     = "heim-"
  subnets         = ["${module.vpc.public_subnets}"]
  security_groups = ["${aws_security_group.lb.id}"]

  tags {
    Config = "heimdall"
  }
}

resource "aws_alb_target_group" "app" {
  name_prefix          = "heim-"
  port                 = "${local.app_port}"
  protocol             = "HTTP"
  vpc_id               = "${module.vpc.vpc_id}"
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    interval          = 6
    healthy_threshold = 2
  }
}

resource "aws_acm_certificate" "certificate" {
  domain_name       = "heimdall.bnch.us"
  validation_method = "EMAIL"

  tags {
    Config = "heimdall"
  }
}

resource "aws_alb_listener" "front-end" {
  load_balancer_arn = "${aws_alb.main.id}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "${aws_acm_certificate.certificate.arn}"

  default_action {
    target_group_arn = "${aws_alb_target_group.app.id}"
    type             = "forward"
  }
}

## Route 53

data "aws_route53_zone" "bnch-us" {
  name = "bnch.us"
}

resource "aws_route53_record" "cname" {
  zone_id = "${data.aws_route53_zone.bnch-us.id}"
  name    = "heimdall.bnch.us"
  type    = "A"

  alias {
    name                   = "${aws_alb.main.dns_name}"
    zone_id                = "${aws_alb.main.zone_id}"
    evaluate_target_health = true
  }
}

## ECS

resource "aws_ecs_cluster" "cluster" {
  name = "heimdall-cluster"
}

resource "aws_ecr_repository" "repo" {
  name = "heimdall"
}

resource "aws_cloudwatch_log_group" "heimdall" {
  name = "/ecs/heimdall"

  tags {
    Config = "heimdall"
  }
}

resource "aws_ecs_task_definition" "app" {
  cpu                      = 256
  execution_role_arn       = "${aws_iam_role.execution-role.arn}"
  family                   = "heimdall"
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = "${aws_iam_role.task-role.arn}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": 256,
    "image": "${aws_ecr_repository.repo.repository_url}:latest",
    "memory": 512,
    "name": "app",
    "networkMode": "awsvpc",
    "environment": [
      {"name": "PORT", "value": "${local.app_port}"},
      {"name": "ANNOUNCEMENTS_CHANNEL_ID", "value": "C0D7T48AY"}
    ],
    "portMappings": [
      {
        "containerPort": ${local.app_port}
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.heimdall.name}",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "app"
      }
    }
  }
]
DEFINITION
}

resource "aws_ecs_service" "service" {
  name            = "heimdall-service"
  cluster         = "${aws_ecs_cluster.cluster.id}"
  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = ["${aws_security_group.app.id}"]
    subnets          = ["${module.vpc.public_subnets}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = "app"
    container_port   = "${local.app_port}"
  }

  depends_on = [
    "aws_alb_listener.front-end",
  ]

  lifecycle {
    ignore_changes = ["task_definition"]
  }
}
