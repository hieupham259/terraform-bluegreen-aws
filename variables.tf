variable "production" {
  description = "Environment serving production traffic: \"blue\" or \"green\". The other environment acts as staging (reachable via path /stg/*)."
  type        = string
  default     = "green"

  validation {
    condition     = contains(["blue", "green"], var.production)
    error_message = "production must be \"blue\" or \"green\"."
  }
}
