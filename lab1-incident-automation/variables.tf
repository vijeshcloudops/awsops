variable "aws_region" {
  description = "AWS Region for every resource in this lab."
  type        = string
  default     = "us-east-1"
}

variable "notification_email" {
  description = "Email address that will receive incident notifications. Confirm the SNS subscription after apply."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "Enter a valid email address for the SNS subscription."
  }
}

variable "instance_type" {
  description = "Small EC2 instance type for the lab. Check current pricing and account eligibility in the selected Region."
  type        = string
  default     = "t3.micro"
}

variable "auto_remediate" {
  description = "Opt in to restarting the lab instance when it stops. Keep false for the first apply and guard test."
  type        = bool
  default     = true
}

variable "owner" {
  description = "Owner tag applied to the EC2 instance and DynamoDB table."
  type        = string
  default     = "portfolio-lab"
}
