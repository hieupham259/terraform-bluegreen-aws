output "vpc" {
  value = {
    vpc_id = data.aws_vpc.default.id
    # The default VPC only has public subnets (one per AZ); map both keys for compatibility
    public_subnets  = data.aws_subnets.default.ids
    private_subnets = data.aws_subnets.default.ids
  }
}

output "namespace" {
  value = local.namespace
}

output "sg" {
  value = {
    lb        = aws_security_group.lb_sg.id
    webserver = aws_security_group.webserver_sg.id
  }
}

output "target_group_arns" {
  value = {
    blue  = [aws_lb_target_group.blue_target_group.arn]
    green = [aws_lb_target_group.green_target_group.arn]
  }
}

output "lb_dns_name" {
  value = aws_lb.lb.dns_name
}