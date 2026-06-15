resource "random_string" "rand" {
  length  = 24
  special = false
  upper   = false
}

locals {
  namespace = var.namespace != "" ? substr(join("-", [var.namespace, random_string.rand.result]), 0, 24) : random_string.rand.result
}

resource "aws_resourcegroups_group" "resourcegroups_group" {
  name = "${local.namespace}-group"

  resource_query {
    query = <<-JSON
      {
        "ResourceTypeFilters": [
          "AWS::AllSupported"
        ],
        "TagFilters": [
          {
            "Key": "ResourceGroup",
            "Values": ["${local.namespace}"]
          }
        ]
      }
    JSON
  }
}
# use the account's default VPC (and its subnets) instead of creating a new one
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security groups are declared WITHOUT inline ingress/egress blocks. Every rule
# is a separate aws_security_group_rule so the SGs never reference each other
# directly. This avoids circular dependencies (and AWS DependencyViolation on
# destroy) and lets each rule be created, updated, or deleted independently.
resource "aws_security_group" "lb_sg" {
  name   = "${local.namespace}-lb-sg"
  vpc_id = data.aws_vpc.default.id

  tags = {
    ResourceGroup = local.namespace
  }
}

resource "aws_security_group" "webserver_sg" {
  name   = "${local.namespace}-webserver-sg"
  vpc_id = data.aws_vpc.default.id

  tags = {
    ResourceGroup = local.namespace
  }
}

# --- lb_sg rules ---
resource "aws_security_group_rule" "lb_ingress_http" {
  type              = "ingress"
  security_group_id = aws_security_group.lb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "lb_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.lb_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- webserver_sg rules ---
resource "aws_security_group_rule" "webserver_ingress_app" {
  type                     = "ingress"
  security_group_id        = aws_security_group.webserver_sg.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb_sg.id
}

resource "aws_security_group_rule" "webserver_ingress_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.webserver_sg.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
}

resource "aws_security_group_rule" "webserver_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.webserver_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_lb" "lb" {
  name            = "${local.namespace}-lb"
  subnets         = data.aws_subnets.default.ids
  security_groups = [aws_security_group.lb_sg.id]
  tags = {
    ResourceGroup = local.namespace
  }
}

resource "aws_lb_target_group" "blue_target_group" {
  name        = "${local.namespace}-blue"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id
  tags = {
    ResourceGroup = local.namespace
  }
  //health_check
}

resource "aws_lb_target_group" "green_target_group" {
  name        = "${local.namespace}-green"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id
  tags = {
    ResourceGroup = local.namespace
  }
  //health_check
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = var.production == "green" ? aws_lb_target_group.green_target_group.arn : aws_lb_target_group.blue_target_group.arn
  }
}


resource "aws_lb_listener_rule" "lb_listener_rule" {
  listener_arn = aws_lb_listener.lb_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = var.production == "green" ? aws_lb_target_group.blue_target_group.arn : aws_lb_target_group.green_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/stg/*"]
    }
  }
}
