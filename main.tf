 #  creating target group for catalogue service.
resource "aws_lb_target_group" "main" {
  name     = "${var.project}-${var.environment}-${var.component}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  port     = local.tg_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  health_check {
    healthy_threshold   = 2
    interval            = 5
    matcher             = "200-299"
    path                = local.health_check_path
    port                = local.tg_port
    timeout             = 2
    unhealthy_threshold = 3
  }
  lifecycle {
    create_before_destroy = true
  }
}

#  creating security group for catalogue service.
resource "aws_instance" "main" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id              = local.private_subnet_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    }
  )
}

#  using terraform data resource to execute the script on the instance which we created.
resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]
  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/${var.component}.sh"
  }
  # make sure you have aws configure in your laptop and have access to the aws account where you are creating the infrastructure
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.main.private_ip
  }
  # we are executing the script on the instance which we created, and this script will install the catalogue service on the instance.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/${var.component}.sh",
      "sudo sh /tmp/${var.component}.sh ${var.component} ${var.environment}"
    ]
  }
}

#catalogue instance state is stopped because we will create AMI from this instance and then we will use this AMI in ASG and whenever ASG will create new instance it will use this AMI and all the configuration will be same as the instance which we created and then created AMI from it.
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on = [terraform_data.main]
}

# taking AMI ID from the instance.
resource "aws_ami_from_instance" "main" {
  name               = "${var.project}-${var.environment}-${var.component}"
  source_instance_id = aws_instance.main.id
  depends_on = [aws_ec2_instance_state.main]
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    }
  )
}

#  terminating the instance after TAKING THE AMI ID.
resource "terraform_data" "main_delete" {
  triggers_replace = [
    aws_instance.main.id
  ]
  
  # make sure you have aws configure in your laptop and have access to the aws account where you are creating the infrastructure
  provisioner "local-exec" {
    command ="aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
  depends_on = [aws_ami_from_instance.main]
}

# creating launch template.
resource "aws_launch_template" "main" {
  name = "${var.project}-${var.environment}-${var.component}"
  image_id = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"
  update_default_version = true # each time u update ,new version will be default
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]

  #instance tags created by ASG
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = "${var.project}-${var.environment}-${var.component}"
      }
    )
  }

#volume tags created by ASG
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${var.project}-${var.environment}-${var.component}"
      }
    )
  }
  #lunch template tags
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    }
  )
}

# creating ASG for catalogue service.
resource "aws_autoscaling_group" "main" {
  name                      = "${var.project}-${var.environment}-${var.component}"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 90
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  target_group_arns         = [aws_lb_target_group.main.arn]
  vpc_zone_identifier       = local.private_subnet_ids

  launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  } 

  dynamic "tag" {
      for_each     = merge(
        {
          Name ="${var.project}-${var.environment}-${var.component}"
        }
      )
      content {
        key                 = tag.key
        value               = tag.value
        propagate_at_launch = true
      }
  }
  #  instance refresh to update the instances .
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    } 
  }

  timeouts {
    delete = "15m"
  }

}

# creating scaling policy for catalogue service.
resource "aws_autoscaling_policy" "main" {
  name                   = "${var.project}-${var.environment}-${var.component}"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"
   target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }
}

# creating listener rule for catalogue service.
resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = var.rule_priority

  action {
    type = "forward"
      target_group_arn = aws_lb_target_group.main.arn
      }
  condition {
    host_header {
      values = [local.rule_header_url]
    }
  }
} 

