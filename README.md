# Outline Server with Ansible/Terraform

This provisions an AWS EC2 instance with Outline Server VPN:

- Amazon Linux AMI
- A 10 GiB `gp3` root volume
- Inbound ports 22, 80, and 443
- Key-only SSH access
- `quay.io/outline/shadowbox:stable` container
- Access keys on port 443
- Management API on port 50443

## Setup

Global settings live in `terraform/global.auto.tfvars.json`. AWS CLI, Terraform, and Ansible must be pre-installed.

```sh
# Install dependencies
ansible-galaxy collection install -r requirements.yml

# Provision, configure, and deploy the server (Terraform, DNS, SSH, OS, fail2ban, Docker, shadowbox, access keys)
ansible-playbook ansible/setup.yml

# Wake the server after the auto-stop alarm fired (start, DNS, health, deploy)
ansible-playbook ansible/start.yml

# Test the server if up and running, stopped servers will fail discovery
ansible-inventory --list
ansible all -m ping
```

Both playbooks are idempotent and safe to re-run. Shared variables live in `ansible/group_vars/`; the Outline API prefix and ports are set there.

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

### TLS Certificates

The self-signed TLS certificate is generated on your machine and uploaded to the server. Files live in `files/outline/` and are reused on every future run.

## Optional settings

- Set the CLOUDFLARE_API_TOKEN environmental variable and terraform vars for Cloudflare DDNS
