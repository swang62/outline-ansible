data "aws_vpc" "default" {
  default = true
}

data "aws_route_table" "main" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "association.main"
    values = [true]
  }
}

data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-x86_64"
}

resource "aws_vpc_ipv6_cidr_block_association" "main" {
  vpc_id                           = data.aws_vpc.default.id
  assign_generated_ipv6_cidr_block = true
}

resource "aws_subnet" "instance" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = cidrsubnet(data.aws_vpc.default.cidr_block, 4, 2)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  ipv6_cidr_block         = cidrsubnet(aws_vpc_ipv6_cidr_block_association.main.ipv6_cidr_block, 8, 0)
}

resource "aws_route" "ipv6_internet" {
  route_table_id              = data.aws_route_table.main.route_table_id
  gateway_id                  = data.aws_internet_gateway.default.id
  destination_ipv6_cidr_block = "::/0"
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
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "ICMP echo"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "ICMPv6 echo"
    from_port        = 128
    to_port          = -1
    protocol         = "icmpv6"
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Shadowbox access keys"
    from_port        = 443
    to_port          = 443
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "Outline management API"
    from_port   = 50443
    to_port     = 50443
    protocol    = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
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
  subnet_id                   = aws_subnet.instance.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  key_name                    = aws_key_pair.instance.key_name
  associate_public_ip_address = true
  ipv6_address_count          = 1

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = var.instance_name
  }

  lifecycle {
    # ponytail: IPs change on every stop/start; don't let them force replacement
    ignore_changes = [ami, associate_public_ip_address, public_ip, private_ip, ipv6_address_count, ipv6_addresses]
  }
}

resource "aws_ec2_instance_state" "instance" {
  instance_id = aws_instance.instance.id
  state       = "running"
}

resource "aws_cloudwatch_metric_alarm" "low_egress" {
  alarm_name          = "awsec2-${aws_instance.instance.id}-LowActivity"
  alarm_description   = "Stops instance ${aws_instance.instance.id} when total network egress stays below threshold for one consecutive hour."
  evaluation_periods  = 4
  datapoints_to_alarm = 4
  metric_name         = "NetworkOut"
  namespace           = "AWS/EC2"
  period              = 900
  statistic           = "Sum"
  threshold           = 100000
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = aws_instance.instance.id
  }

  alarm_actions = ["arn:aws:automate:${var.aws_region}:ec2:stop"]
}
