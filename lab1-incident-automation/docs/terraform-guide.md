# Terraform Walkthrough

This deploys the same operational workflow as the console guide. Use one path at a time; running both creates two independent sets of resources. Terraform does not manage the console-created stack.

## 1. Prepare inputs

From this repository directory, copy the example file and edit it:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Set `notification_email` to an address you can confirm. Keep `auto_remediate = false` for the initial apply and guard test. Choose one AWS Region for all resources. The checked-in example uses `us-east-1` and `t3.micro`; availability and pricing vary by account and Availability Zone.

Terraform must have credentials from an AWS CLI profile, environment-based credentials, or another supported provider credential source. Do not put access keys in Terraform files.

## 2. Initialize and inspect the plan

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the plan before applying. It should include one EC2 instance, SNS topic and email subscription, DynamoDB table, Lambda function, Lambda IAM role and policies, CloudWatch log group, EventBridge rule and target, and Lambda invoke permission. There should be no SQS resources. Confirm the Region, email, instance type, and `AutoRemediate` setting.

## 3. Apply

```powershell
terraform apply
```

Review the final plan and type `yes` when ready. Confirm the email subscription using the message from SNS. Terraform may report the subscription resource as pending until it is confirmed.

Record outputs:

```powershell
terraform output
```

The selected Availability Zone is exposed as `instance_availability_zone`. Terraform checks which default-VPC subnet AZs offer the chosen instance type before selecting a subnet. This avoids pinning `t3.micro` to an unsupported zone such as the earlier `us-east-1e` case.

## 4. Test notification-only behavior

1. Verify the instance is running and its `AutoRemediate` tag is `false`.
2. Stop it in the EC2 console.
3. Open CloudWatch Logs group `/aws/lambda/lab1-incident-handler` and inspect the latest log stream. Expect `manual-action-required`.
4. Confirm the SNS email arrives, DynamoDB table `lab1-incident-processed-events` has an item keyed by `eventId`, and EC2 remains stopped.

## 5. Test automatic restart

Change the tag through Terraform:

```powershell
terraform apply -var="auto_remediate=true"
```

Start the instance, wait for **Running**, and stop it again. The handler should log and email `start-requested`, and the instance should return to **Running**. Return to the safe setting afterward:

```powershell
terraform apply -var="auto_remediate=false"
```

The code's variable default is currently `true`, while the checked-in `.tfvars.example` explicitly selects `false` for the first test. Keep using the example file so the initial behavior is unambiguous.

## What Terraform creates

- **EC2:** Amazon Linux 2023 from the AWS public SSM parameter, 8 GB encrypted gp3 root volume, required IMDSv2, no public IP, and `Project`, `Owner`, `Name`, and `AutoRemediate` tags.
- **EventBridge:** default-bus rule filtered to the exact instance ARN and the `stopped` state; Lambda target and invoke permission.
- **Lambda:** Python 3.13, handler `lambda_function.handler`, 30-second timeout, 128 MB, SNS and DynamoDB environment variables.
- **DynamoDB:** on-demand table named `lab1-incident-processed-events`, string partition key `eventId`.
- **SNS:** topic `lab1-incident-alerts` and email subscription.
- **IAM:** dedicated Lambda role, managed basic logging policy, and an inline policy scoped to the table, topic, and lab EC2 instance. Starting the instance additionally requires resource tag `AutoRemediate=true`.
- **CloudWatch Logs:** Lambda log group with 14-day retention.

The Lambda artifact `lambda.zip` is generated from the checked-in Python file by Terraform's archive provider. It is a deployment artifact and is ignored by Git.

## Cleanup

After confirming `AutoRemediate=false`, destroy only if this Terraform directory owns the resources:

```powershell
terraform plan -destroy
terraform destroy
```

Review the destroy plan and confirm. This terminates the EC2 instance and removes the associated lab resources. Terraform state contains resource metadata and identifiers; keep it private and do not commit it. Deleting a console-created stack is a separate operation.
