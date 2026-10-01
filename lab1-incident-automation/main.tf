data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

data "aws_ec2_instance_type_offerings" "demo" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name_prefix = "lab1-incident"
  common_tags = {
    Project = "Lab1"
    Owner   = var.owner
  }
  compatible_subnet_ids = sort([
    for subnet_id, subnet in data.aws_subnet.default : subnet_id
    if contains(data.aws_ec2_instance_type_offerings.demo.locations, subnet.availability_zone)
  ])
  instance_arn = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.demo.id}"
}

resource "aws_sns_topic" "incidents" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.incidents.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_instance" "demo" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = try(local.compatible_subnet_ids[0], null)
  associate_public_ip_address = false

  lifecycle {
    precondition {
      condition     = length(local.compatible_subnet_ids) > 0
      error_message = "No default-VPC subnet is in an Availability Zone offering instance type ${var.instance_type}. Choose another instance type or add a compatible subnet."
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = 8
  }

  tags = merge(local.common_tags, {
    Name          = "lab1-ops-demo"
    AutoRemediate = var.auto_remediate ? "true" : "false"
  })
}

resource "aws_dynamodb_table" "processed_events" {
  name         = "${local.name_prefix}-processed-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "eventId"

  attribute {
    name = "eventId"
    type = "S"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-handler"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_actions" {
  name = "${local.name_prefix}-actions"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadInstanceState"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid      = "StartOnlyOptedInLabInstance"
        Effect   = "Allow"
        Action   = "ec2:StartInstances"
        Resource = local.instance_arn
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/AutoRemediate" = "true"
          }
        }
      },
      {
        Sid      = "RecordProcessedEvents"
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.processed_events.arn
      },
      {
        Sid      = "PublishIncidentNotification"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.incidents.arn
      }
    ]
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "handler" {
  function_name    = "${local.name_prefix}-handler"
  description      = "Triage EC2 stopped events and restart only explicitly opted-in instances."
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      SNS_TOPIC_ARN       = aws_sns_topic.incidents.arn
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.processed_events.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_actions,
    aws_iam_role_policy_attachment.lambda_logs
  ]

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "instance_stopped" {
  name           = "${local.name_prefix}-instance-stopped"
  description    = "Invoke incident handler when the lab EC2 instance enters stopped state."
  event_bus_name = "default"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    resources     = [local.instance_arn]
    detail = {
      state = ["stopped"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.instance_stopped.name
  event_bus_name = "default"
  target_id      = "incident-handler"
  arn            = aws_lambda_function.handler.arn

}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvokeLab1"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_stopped.arn
}
