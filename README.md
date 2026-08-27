# Outline Server with Ansible/Terraform

This provisions an AWS EC2 instance with:

- Amazon Linux AMI
- A 10 GiB `gp3` root volume
- Inbound TCP ports 22, 80, and 443
- Key-only SSH access

## Setup

Global settings live in `terraform/global.auto.tfvars.json`. AWS CLI, Terraform, and Ansible must be pre-installed.

```sh
# Install dependencies
ansible-galaxy collection install -r requirements.yml
ansible-playbook ansible/playbook.yml

# Test the server
ansible-inventory --list
ansible all -m ping
```

## Credentials

### AWS credentials

Install and configure the AWS CLI with admin credentials:

```sh
aws configure
aws sts get-caller-identity
```

### SSH key

Create the local key pair before you run the playbook:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/outline-ec2 -C outline-ec2
chmod 600 ~/.ssh/outline-ec2
```

## Optional settings

- To restrict SSH, set `ssh_ingress_cidrs` to your own IP or trusted CIDRs
- Set the CLOUDFLARE_API_TOKEN environmental variable and terraform global vars for optional Cloudflare DDNS to always point at your server's dynamic IP
