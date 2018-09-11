output "replicated_console_password" {
  value = "${random_pet.console_password.id}"
}

output "encryption_password" {
  value = "${var.encryption_password != "" ? var.encryption_password : random_pet.enc_password.id}"
}

output "replicated_console_url" {
  value = "https://${var.hostname}:8800"
}

output "ptfe_endpoint" {
  value = "https://${var.hostname}"
}

output "ptfe_health_check" {
  value = "https://${var.hostname}/_health_check"
}
