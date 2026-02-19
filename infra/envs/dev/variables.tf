variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cost-guardian"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "slack_webhook_url" {
	description = "Slack webhook URL"
	type = string
	sensitive = true
}
