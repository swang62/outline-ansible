# Outline Server with Ansible/Terraform

This provisions an AWS EC2 instance with:

- Amazon Linux AMI
- A 10 GiB `gp3` root volume
- Inbound TCP ports 22, 80, and 443
- Key-only SSH access
- A dynamic Ansible inventory to track IP

## Setup

Global settings for Terraform and Ansible live in `terraform/global.auto.tfvars.json`. Terraform and Ansible use your default AWS CLI credentials.

```sh
ansible-galaxy collection install -r requirements.yml
ansible-playbook ansible/playbook.yml
ansible-inventory --list
ansible all -m ping
```

### Optional settings

- To restrict SSH, set `ssh_ingress_cidrs` to one or more trusted CIDRs
- AWS region can also be updated in `terraform/global.auto.tfvars.json`
- Set the API token ENV and zone/DNS variables for optional Cloudflare DDNS

```sh
export CLOUDFLARE_API_TOKEN='your-token'
ansible-playbook ansible/playbook.yml
```
