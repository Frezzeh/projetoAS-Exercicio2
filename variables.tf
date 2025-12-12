variable "admin_username" {
  description = "Username"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Password"
  type        = string
  sensitive   = true
}
