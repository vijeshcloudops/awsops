output "instance_id" {
  description = "EC2 instance managed by this lab."
  value       = aws_instance.demo.id
}

output "instance_arn" {
  description = "Instance ARN used to scope the Lambda restart permission and EventBridge rule."
  value       = local.instance_arn
}

output "instance_availability_zone" {
  description = "Availability Zone selected from those offering the configured instance type."
  value       = aws_instance.demo.availability_zone
}

output "lambda_function_name" {
  description = "Incident handler Lambda function."
  value       = aws_lambda_function.handler.function_name
}

output "sns_topic_arn" {
  description = "SNS topic for incident notifications. Confirm the email subscription after apply."
  value       = aws_sns_topic.incidents.arn
}

output "eventbridge_rule_name" {
  description = "Rule matching stopped events for the lab instance."
  value       = aws_cloudwatch_event_rule.instance_stopped.name
}
