variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {
  description = "SSH Keypair"
  type        = string
}

variable "public_key_path" {
  description = "SSH public key path"
  type        = string
}

variable "domain_name" {
  description = "DuckDNS or custom domain"
  type        = string
}

variable "vpc_name" {
  description = "Name tag of the VPC to deploy into"
  type        = string
  default     = "Ajax-VPC"
}

variable "ssh_user" {
  description = "SSH user for the EC2 instance AMI"
  type        = string
  default     = "ubuntu"
}
