variable "aws_region" {
  description = "AWS region for the infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for the Ubuntu EC2 instance."
  type        = string
  default     = "ami-0fc5d935ebf8bc3bc"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "Single trusted IPv4 CIDR permitted to connect over SSH."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && can(regex("/32$", var.ssh_allowed_cidr))
    error_message = "ssh_allowed_cidr must be a single IPv4 address in /32 CIDR notation."
  }
}

variable "app_port" {
  description = "Port used by the intern-task-app container."
  type        = number
  default     = 5000
}
