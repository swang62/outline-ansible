data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-x86_64"
}

resource "aws_key_pair" "instance" {
  key_name   = "${var.instance_name}-${var.aws_region}"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "instance" {
  name        = var.instance_name
  description = "Web and SSH access for ${var.instance_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_ingress_cidrs
  }

  ingress {
    description = "ICMP echo"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.instance_name
  }
}

resource "aws_instance" "instance" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  key_name                    = aws_key_pair.instance.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = var.instance_name
  }
}

resource "aws_ec2_instance_state" "instance" {
  instance_id = aws_instance.instance.id
  state       = "running"
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "awsec2-${aws_instance.instance.id}-LowActivity"
  alarm_description   = "Stops instance ${aws_instance.instance.id} when CPU is below 1.5% and maximum egress is below 1 MB/s for 4 consecutive 15-minute periods."
  evaluation_periods  = 4
  datapoints_to_alarm = 4
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "low_activity"
    expression  = "IF(cpu < 1.5 AND egress_rate < 1000000, 1, 0)"
    label       = "Low CPU and network egress"
    return_data = true
  }

  metric_query {
    id = "cpu"

    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/EC2"
      period      = 900
      stat        = "Average"

      dimensions = {
        InstanceId = aws_instance.instance.id
      }
    }
  }

  metric_query {
    id          = "egress_rate"
    expression  = "egress / PERIOD(egress)"
    label       = "Maximum egress rate"
    return_data = false
  }

  metric_query {
    id = "egress"

    metric {
      metric_name = "NetworkOut"
      namespace   = "AWS/EC2"
      period      = 900
      stat        = "Maximum"

      dimensions = {
        InstanceId = aws_instance.instance.id
      }
    }
  }
}
