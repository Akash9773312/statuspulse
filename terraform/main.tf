data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

resource "aws_key_pair" "statuspulse" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_security_group" "statuspulse_sg" {
  name   = "statuspulse-sg"
  vpc_id = data.aws_vpc.selected.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
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
}

resource "aws_eip" "statuspulse" {
  domain = "vpc"

  tags = {
    Name = "statuspulse-eip"
  }
}

resource "aws_instance" "statuspulse" {
  ami                    = "ami-0f58b397bc5c1f2e8"
  instance_type          = var.instance_type
  key_name               = aws_key_pair.statuspulse.key_name
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.statuspulse_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  user_data = file("${path.module}/userdata.sh.tpl")

  tags = {
    Name        = "statuspulse"
    Environment = "production"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eip_association" "statuspulse" {
  instance_id   = aws_instance.statuspulse.id
  allocation_id = aws_eip.statuspulse.id
}
