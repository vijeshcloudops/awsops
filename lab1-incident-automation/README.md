# Lab 1: EC2 Stop-Event Incident Automation

A hands-on AWS operations lab: when the lab EC2 instance stops, Amazon EventBridge routes its state-change event to AWS Lambda. Lambda records the event in DynamoDB, sends an SNS email, and starts the instance only when its `AutoRemediate` tag is set to `true`.

This repository is organized for teaching in this order: build and test it in the AWS Console first, then reproduce it with Terraform.

## Learning outcomes

- Build an event-driven operational workflow using EC2, EventBridge, Lambda, DynamoDB, SNS, CloudWatch Logs, and IAM.
- Create a least-privilege Lambda execution role and understand the difference between its trust policy and permissions policy.
- Use an opt-in resource tag as a remediation guard.
- Record EventBridge event IDs idempotently with a DynamoDB conditional write.
- Verify behavior from service consoles and Lambda logs, then manage the same design as infrastructure as code.

## Architecture

See [the architecture and event flow](docs/architecture.md) for the diagram, decisions, and IAM boundaries.

## Follow the lab

1. [Console-first walkthrough](docs/console-guide.md): create each service, connect the event flow, and test notification-only and auto-remediation behavior.
2. [Terraform walkthrough](docs/terraform-guide.md): deploy the equivalent workflow and run the same tests.
3. [Troubleshooting](docs/troubleshooting.md): diagnose common setup, invocation, permission, and notification problems.

The Lambda source is [lambda/lambda_function.py](lambda/lambda_function.py). Terraform details and resource names are in the root `.tf` files.

## Resources created

- One small Amazon Linux EC2 instance, with no inbound access required for this lab.
- One EventBridge rule, Lambda target, and Lambda invoke permission.
- One Lambda function and a dedicated IAM execution role.
- One DynamoDB on-demand table for processed event IDs.
- One SNS topic and email subscription.
- One CloudWatch log group with 14-day retention.

There is **no SQS queue** in this lab. The first console exercise uses `lab1-processed-events` for its DynamoDB table; Terraform uses `lab1-incident-processed-events`. Lambda receives the actual table name through its environment variable in either deployment path.

## Prerequisites and costs

You need an AWS account with permission to create the resources above, an email address you can confirm, Terraform 1.6+, and internet access for Terraform provider downloads. AWS prices, free-tier eligibility, service quotas, and available instance types vary. Review current pricing before applying, and destroy resources when finished. Stopping an EC2 instance does not remove its EBS volume or every other billable resource.

Use one deployment path at a time in an account: the console-created resources and Terraform-created resources are separate stacks. Do not manually modify or delete Terraform-managed resources while relying on Terraform state.

## Safety

Start with `AutoRemediate=false` and verify that the workflow records and notifies without restarting the instance. Enable it only for this disposable lab instance. An automatic restart can interfere with planned maintenance in a real environment, so production systems need ownership, maintenance-window, and policy controls beyond this teaching example. EC2 termination protection is not the focus here: this lab tests stopping, and stop protection must not be enabled on the instance while performing the manual stop test.

## Repository contents

```text
.
|-- README.md
|-- docs/
|   |-- architecture.md
|   |-- console-guide.md
|   |-- terraform-guide.md
|   `-- troubleshooting.md
|-- lambda/
|   `-- lambda_function.py
|-- main.tf
|-- outputs.tf
|-- variables.tf
|-- versions.tf
|-- terraform.tfvars.example
`-- .gitignore
```

Do not commit `terraform.tfvars`, Terraform state, saved plans, credentials, or personal email addresses.

## Cleanup

For Terraform resources, follow the final cleanup step in the [Terraform walkthrough](docs/terraform-guide.md). For console resources, follow the cleanup checklist at the end of the [console walkthrough](docs/console-guide.md). Remove only the stack you created; do not use Terraform to clean up console-created resources.
