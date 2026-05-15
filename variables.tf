variable "project_name" {
  default = "student-records-app"
}

variable "db_username" {
  description = "Database master username"
  default     = "RanjHussein"
}

variable "db_password" {
  description = "Database master password (sensitive)"
  default     = "123ThisisTheBestPasswordImaginable123" # Change this before applying!
  sensitive   = true
}