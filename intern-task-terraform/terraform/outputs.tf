output "instance_public_ip" {
  description = "Public IPv4 address of the application instance."
  value       = aws_instance.app.public_ip
}

output "app_port" {
  description = "Port exposed by the application."
  value       = var.app_port
}
