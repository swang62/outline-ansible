variable "aws_region" {
  description = "AWS region in which to launch the instance."
  type        = string
}

variable "instance_name" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ssh_public_key_path" {
  description = "Local path to the public key installed on the instance."
  type        = string
}

variable "cloudflare_zone" {
  type = string
}

variable "cloudflare_dns_name" {
  type = string
}
