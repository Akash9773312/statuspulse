# Terraform — StatusPulse infrastructure

Provisions AWS resources for StatusPulse on a **free-tier** `t2.micro` with a **stable Elastic IP**.

## What it creates

- EC2 instance (Ubuntu) in your VPC (`Ajax-VPC` by default)
- Security group (SSH 22, HTTP 80, HTTPS 443)
- Elastic IP + association (IP persists across instance replacement)
- AWS SSH key pair from your local public key

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- AWS CLI configured (`aws configure`)
- VPC with a public subnet (`map-public-ip-on-launch = true`)

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # if you add an example file
# Edit terraform.tfvars

terraform init
terraform plan
terraform apply
```

Or from repo root:

```bash
cd scripts && python3 bootstrap.py
```

## Variables

| Name | Description |
|------|-------------|
| `domain_name` | StatusPulse HTTPS domain |
| `kuma_domain_name` | Uptime Kuma HTTPS domain |
| `vpc_name` | VPC Name tag |
| `public_key_path` | Local SSH public key |
| `key_name` | AWS key pair name |
| `instance_type` | Default `t2.micro` |
| `aws_region` | Default `ap-south-1` |

## Outputs

```bash
terraform output server_ip
terraform output app_url
terraform output kuma_url
```

## Destroy

```bash
terraform destroy
```

Back up PostgreSQL before destroying (`scripts/backup.sh`).
