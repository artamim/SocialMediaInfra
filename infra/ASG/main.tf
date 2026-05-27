terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# ==================== Data Sources ====================
data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "allow_all_demo" {
  name   = "allow-all-traffic"
  vpc_id = data.aws_vpc.default.id
}

# ==================== Auto Scaling Group ====================
resource "aws_autoscaling_group" "fastapi_asg" {
  name                = "fastapi-asg"
  vpc_zone_identifier = [
    "subnet-067be4a2b0b962e31",
    "subnet-0b938a6a3e4009d7d",
    "subnet-0b3c13c72df65ffa3"
  ]

  min_size         = 2
  max_size         = 3
  desired_capacity = 2

  launch_template {
    id      = "lt-0f99900780c7ee456"
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "fastapi-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Staging"
    propagate_at_launch = true
  }
}

# CPU Target Tracking Policy
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "fastapi-cpu-50-target"
  autoscaling_group_name = aws_autoscaling_group.fastapi_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = 50.0
    disable_scale_in = false
  }
}