import json
import os

import boto3


ecs = boto3.client("ecs")


def handler(event, context):
    region = os.environ["AWS_REGION"]
    sns_publish_enabled = os.environ.get("SNS_PUBLISH_ENABLED", "false").lower() == "true"

    if not sns_publish_enabled:
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(
                {
                    "message": "dispatch dry run",
                    "region": region,
                    "task_arn": None,
                    "sns_published": False,
                }
            ),
        }

    result = ecs.run_task(
        cluster=os.environ["ECS_CLUSTER_ARN"],
        taskDefinition=os.environ["TASK_DEFINITION_ARN"],
        launchType="FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": [s.strip() for s in os.environ["SUBNET_IDS"].split(",") if s.strip()],
                "securityGroups": [
                    s.strip() for s in os.environ["SECURITY_GROUP_IDS"].split(",") if s.strip()
                ],
                "assignPublicIp": "ENABLED",
            }
        },
        count=1,
    )

    failures = result.get("failures", [])
    if failures:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "dispatch failed", "failures": failures, "region": region}),
        }

    tasks = result.get("tasks", [])
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "dispatch ok",
                "region": region,
                "task_arn": tasks[0]["taskArn"] if tasks else None,
                "sns_published": True,
            }
        ),
    }
