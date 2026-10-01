import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

table = dynamodb.Table(os.environ["DYNAMODB_TABLE_NAME"])
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def notify(payload):
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Lab 1 EC2 incident",
        Message=json.dumps(payload, indent=2, default=str),
    )


def handler(event, context):
    event_id = event.get("id")
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id")
    event_state = detail.get("state")

    if not event_id or not instance_id:
        raise ValueError("Event is missing its ID or EC2 instance ID")

    if event_state != "stopped":
        logger.info("Ignoring event with state=%s", event_state)
        return {"action": "ignored", "reason": "not-stopped"}

    try:
        table.put_item(
            Item={"eventId": event_id},
            ConditionExpression="attribute_not_exists(eventId)",
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            logger.info("Duplicate event ignored: %s", event_id)
            return {"action": "ignored", "reason": "duplicate-event"}
        raise

    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response["Reservations"][0]["Instances"][0]
    tags = {tag["Key"]: tag["Value"] for tag in instance.get("Tags", [])}
    current_state = instance["State"]["Name"]

    incident = {
        "eventId": event_id,
        "instanceId": instance_id,
        "eventState": event_state,
        "currentState": current_state,
        "autoRemediate": tags.get("AutoRemediate", "false"),
        "project": tags.get("Project", "unknown"),
    }

    if tags.get("AutoRemediate", "false").lower() != "true":
        incident["action"] = "manual-action-required"
        incident["message"] = "AutoRemediate is not true; instance was not started."
    elif current_state != "stopped":
        incident["action"] = "no-action"
        incident["message"] = "Instance is no longer stopped; it may already be starting."
    else:
        ec2.start_instances(InstanceIds=[instance_id])
        incident["action"] = "start-requested"
        incident["message"] = "Restart requested for the opted-in lab instance."

    logger.info(json.dumps(incident))
    notify(incident)
    return incident
