# Troubleshooting

| Symptom | Check |
|---|---|
| `SyntaxError` on line 1 | Paste only the Python source into Lambda. Do not include Markdown fences, explanatory labels such as `lambda code:`, or shell prompts. Deploy the edited code. |
| `Runtime.HandlerNotFound` | Runtime settings must use `lambda_function.handler`: the file/module is `lambda_function.py`, and its entry function is `handler`. |
| `KeyError: SNS_TOPIC_ARN` | Add an environment variable whose **key** is exactly `SNS_TOPIC_ARN`; its **value** is the SNS topic ARN. Do not use the ARN as the key. |
| `KeyError: DYNAMODB_TABLE_NAME` | Set this key to the exact table name in the same Region. Console path: `lab1-processed-events`; Terraform path: `lab1-incident-processed-events`. |
| Lambda is not invoked | Verify the EventBridge rule is enabled, uses the default event bus, matches `aws.ec2` / `EC2 Instance State-change Notification` / state `stopped`, targets the correct Lambda, and has permission to invoke it. Check Region and instance ARN. |
| Instance remains stopped | This is expected when `AutoRemediate` is absent or not the lowercase value `true`. Also check that the instance is still stopped when Lambda checks its current state. `AutoRemediate=false` yields `manual-action-required`. |
| `AccessDenied` in Lambda logs | Check the Lambda execution role. It needs basic CloudWatch Logs access, `ec2:DescribeInstances`, scoped `ec2:StartInstances` with the tag condition, `dynamodb:PutItem` for the table, and `sns:Publish` for the topic. The EventBridge invoke permission is separate from the execution role. |
| No email | Confirm the SNS email subscription and inspect the SNS topic ARN configured in Lambda. Check spam/quarantine folders and function logs for publish errors. |
| DynamoDB item not created | Verify table name, Region, partition key `eventId` (String), and the role's `dynamodb:PutItem` resource ARN. |
| A duplicate event appears ignored | The function conditionally stores each EventBridge `id`; a repeated delivery of the same ID is intentionally ignored. A new stop operation should have a new event ID. |
| `t3.micro` unsupported in selected AZ | In the console, select a compatible AZ or avoid pinning one. Terraform discovers compatible default-VPC subnet AZs automatically; inspect `instance_availability_zone` output. |
| Terraform plans unexpected replacement/deletion | Stop and inspect the full plan. Check whether variables or manually edited Terraform-managed resources changed. Do not approve an unfamiliar destroy or replacement. |

Useful checks: Lambda **Monitor** and its CloudWatch log group, EventBridge rule **Monitoring**, SNS subscription status, DynamoDB table items, EC2 state and tags, and IAM role policies. There is no SQS queue in this lab.
