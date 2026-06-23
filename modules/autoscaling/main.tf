# create instance and autoscaling group and lb listeners
# IAM role + instance profile cho webserver

# Trust policy
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Permissions policy
data "aws_iam_policy_document" "permissions" {
  statement {
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "webserver" {
  name               = "${var.base.namespace}-${var.label}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    ResourceGroup = var.base.namespace
  }
}

resource "aws_iam_policy" "webserver" {
  name   = "${var.base.namespace}-${var.label}-policy"
  policy = data.aws_iam_policy_document.permissions.json

  tags = {
    ResourceGroup = var.base.namespace
  }
}

resource "aws_iam_role_policy_attachment" "webserver" {
  role       = aws_iam_role.webserver.name
  policy_arn = aws_iam_policy.webserver.arn
}

resource "aws_iam_instance_profile" "webserver" {
  name = "${var.base.namespace}-${var.label}-profile"
  role = aws_iam_role.webserver.name

  tags = {
    ResourceGroup = var.base.namespace
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  html    = templatefile("${path.module}/server/index.html", { NAME = join("-", [var.label, var.app_version]), BG_COLOR = var.label })
  startup = templatefile("${path.module}/server/startup.sh", { HTML = local.html })
}

resource "aws_launch_template" "webserver" {
  name_prefix   = var.base.namespace
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  user_data     = base64encode(local.startup)
  key_name      = var.ssh_keypair
  iam_instance_profile {
    name = aws_iam_instance_profile.webserver.name
  }
  vpc_security_group_ids = [var.base.sg.webserver]
  tags = {
    ResourceGroup = var.base.namespace
  }
}

resource "aws_autoscaling_group" "webserver" {
  name     = "${var.base.namespace}-${var.label}-asg"
  min_size = 1
  max_size = 1
  //vpc_zone_identifier = var.base.vpc.private_subnets
  vpc_zone_identifier = var.base.vpc.public_subnets
  target_group_arns   = var.label == "green" ? var.base.target_group_arns.green : var.base.target_group_arns.blue
  launch_template {
    id      = aws_launch_template.webserver.id
    version = aws_launch_template.webserver.latest_version
  }
  tag {
    key                 = "ResourceGroup"
    value               = var.base.namespace
    propagate_at_launch = true
  }
  tag {
    key                 = "Name"
    value               = "${var.base.namespace}-${var.label}"
    propagate_at_launch = true
  }
}

