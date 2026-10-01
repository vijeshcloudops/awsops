# Console-First Walkthrough

This guide builds the workflow manually before introducing Terraform. AWS console labels can change; the service names and required configuration below are the important parts. Use the same AWS Region throughout (examples use `us-east-1`). Do not enable EC2 stop protection during the lab's manual stop test.

## 1. Create the SNS topic

1. Open **Amazon SNS** and select **Topics** > **Create topic**.
2. Choose **Standard**, name it `lab1-incident-alerts`, and create it.
3. Open the topic and choose **Create subscription**. Set protocol to **Email**, enter an address you can access, and create the subscription.
4. Open the confirmation email and confirm the subscription. Until it is confirmed, notifications will not arrive.
5. Keep the topic ARN available for the Lambda environment variable.

## 2. Launch the lab EC2 instance

1. Open **EC2** > **Instances** > **Launch instances**. Name it `lab1-ops-demo`.
2. Choose an Amazon Linux 2023 64-bit x86 AMI and a small eligible type such as `t3.micro`. If the selected Availability Zone does not support that type, choose a compatible zone or leave zone placement automatic. The earlier `us-east-1e` error was an instance-type offering mismatch, not a Lambda problem.
3. A key pair and inbound security-group rule are not required; this lab never connects to the guest OS. Use the default VPC and a subnet in a compatible Availability Zone. The Terraform version does not assign a public IP.
4. In **Advanced details**, leave shutdown behavior at its normal setting and make sure stop protection is disabled. Termination protection is a separate setting and is not needed to test this lab.
5. Add these resource tags (under **Tags** / **Add additional tags** in the launch flow; the section may be outside Advanced details):

   | Key | Value |
   |---|---|
   | `Project` | `Lab1` |
   | `Owner` | your name or portfolio-lab |
   | `AutoRemediate` | `false` |

   The instance name field creates the `Name=lab1-ops-demo` tag. Verify all tags on the instance's **Tags** tab after launch.
6. Launch the instance and record its instance ID and ARN. Wait until it is **Running** before continuing.

## 3. Create the DynamoDB table

1. Open **DynamoDB** > **Tables** > **Create table**.
2. Set table name to `lab1-processed-events`.
3. Set partition key to `eventId`, type **String**. Leave sort key unset.
4. Select **On-demand** capacity and create the table. No secondary indexes or TTL are needed for this lab.

## 4. Create the Lambda execution role

The role has two parts: a trust policy lets the Lambda service assume the role; permission policies let the function call specific services.

1. Open **IAM** > **Roles** > **Create role**. Choose **AWS service** as the trusted entity and **Lambda** as the use case.
2. Attach the AWS managed policy `AWSLambdaBasicExecutionRole` for CloudWatch Logs.
3. Name the role `lab1-incident-lambda-role` and create it.
4. Open the role, choose **Add permissions** > **Create inline policy**, and use the JSON editor. Replace `<REGION>`, `<ACCOUNT_ID>`, and `<INSTANCE_ID>` with your values. The table and topic names below are the names created in this console guide.

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "ReadInstanceState",
         "Effect": "Allow",
         "Action": "ec2:DescribeInstances",
         "Resource": "*"
       },
       {
         "Sid": "StartOnlyOptedInLabInstance",
         "Effect": "Allow",
         "Action": "ec2:StartInstances",
         "Resource": "arn:aws:ec2:<REGION>:<ACCOUNT_ID>:instance/<INSTANCE_ID>",
         "Condition": {
           "StringEquals": {
             "ec2:ResourceTag/AutoRemediate": "true"
           }
         }
       },
       {
         "Sid": "RecordProcessedEvents",
         "Effect": "Allow",
         "Action": "dynamodb:PutItem",
         "Resource": "arn:aws:dynamodb:<REGION>:<ACCOUNT_ID>:table/lab1-processed-events"
       },
       {
         "Sid": "PublishIncidentNotification",
         "Effect": "Allow",
         "Action": "sns:Publish",
         "Resource": "arn:aws:sns:<REGION>:<ACCOUNT_ID>:lab1-incident-alerts"
       }
     ]
   }
   ```

5. Choose **Next**, name the policy `lab1-incident-actions`, review it, and create it. Keep `ec2:StartInstances` scoped to this instance and the tag condition; do not replace it with broad `ec2:*` permissions.

## 5. Create the Lambda function

1. Open **Lambda** > **Functions** > **Create function**. Choose **Author from scratch**.
2. Name it `lab1-incident-handler`. Choose Python 3.12 or newer available in the console, architecture `x86_64`, and **Use an existing role** > `lab1-incident-lambda-role`.
3. Create the function. In **Code**, replace the starter content in `lambda_function.py` with the complete contents of the repository's `lambda/lambda_function.py`, then choose **Deploy**. Do not paste a Markdown code fence or text such as `lambda code:` into the editor.
4. In **Runtime settings** > **Edit**, set the handler to `lambda_function.handler`, then save. The module name is `lambda_function`; the function name in the code is `handler`.
5. Under **Configuration** > **Environment variables**, add:

   | Key | Value |
   |---|---|
   | `SNS_TOPIC_ARN` | ARN of `lab1-incident-alerts` |
   | `DYNAMODB_TABLE_NAME` | `lab1-processed-events` |

6. Set timeout to 30 seconds. Save changes.

## 6. Connect EventBridge to Lambda

1. Open **Amazon EventBridge** > **Rules** > **Create rule**. Use the default event bus and name the rule `lab1-incident-instance-stopped`.
2. Choose **Rule with an event pattern**. Select AWS events, source `aws.ec2`, and detail type **EC2 Instance State-change Notification**. Use a custom pattern if needed to include the exact instance ID:

   ```json
   {
     "source": ["aws.ec2"],
     "detail-type": ["EC2 Instance State-change Notification"],
     "resources": ["arn:aws:ec2:<REGION>:<ACCOUNT_ID>:instance/<INSTANCE_ID>"],
     "detail": {
       "state": ["stopped"]
     }
   }
   ```

3. Choose **AWS service** as target, then **Lambda function**, and select `lab1-incident-handler`.
4. Finish creating the rule. If the console asks to add permission for EventBridge to invoke the function, allow it. Confirm the rule is enabled and the Lambda appears as its target.

## 7. Test notification-only behavior

1. Confirm the instance is **Running**, the `AutoRemediate` tag is `false`, the SNS subscription is confirmed, and the EventBridge rule is enabled.
2. From EC2, choose **Instance state** > **Stop instance**. Wait for the instance to reach **Stopped**; event processing can take a short while.
3. In Lambda **Monitor** > **View CloudWatch logs**, open the newest log stream. Expect a JSON incident with `action` equal to `manual-action-required`.
4. Verify the SNS email arrives and the DynamoDB table contains an `eventId` item. The EC2 instance should remain stopped.

## 8. Test the opt-in restart

1. Start the instance and wait until it is **Running**.
2. In EC2 **Tags**, change `AutoRemediate` to `true` and save. Verify the exact spelling and lowercase value.
3. Stop the instance again and wait for event processing.
4. Check Lambda logs and SNS email for `start-requested`; the instance should transition back to **Running**.
5. Set `AutoRemediate` back to `false` when you finish testing.

## Verify and clean up

The Lambda logs are under `/aws/lambda/lab1-incident-handler`. Check the rule's **Monitoring** page for invocations and the DynamoDB item for the event ID. Each actual stop generates a new event ID; a duplicate delivery with the same ID is ignored.

Delete only the console-created resources when finished: disable/delete the EventBridge rule, delete the Lambda function, delete the IAM role after the function is removed, delete the DynamoDB table, delete the SNS subscription/topic, and terminate the EC2 instance. Confirm the EC2 instance ID before terminating. This console stack is separate from Terraform resources.
