import json
import os
import uuid
from datetime import datetime, timezone

import boto3


dynamodb = boto3.resource("dynamodb")


def handler(event, context):
    region = os.environ["AWS_REGION"]
    table_name = os.environ["TABLE_NAME"]
    sns_publish_enabled = os.environ.get("SNS_PUBLISH_ENABLED", "false").lower() == "true"

    table = dynamodb.Table(table_name)
    request_id = str(uuid.uuid4())

    table.put_item(
        Item={
            "request_id": request_id,
            "region": region,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    )

    payload = {
        "email": os.environ["CANDIDATE_EMAIL"],
        "source": "Lambda",
        "region": region,
        "repo": os.environ["REPO_URL"],
    }

    if sns_publish_enabled:
        topic_arn = os.environ["VERIFICATION_TOPIC_ARN"]
        topic_region = topic_arn.split(":")[3]
        sns = boto3.client("sns", region_name=topic_region)
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(payload),
        )
    else:
        print(f"SNS dry run payload: {json.dumps(payload, separators=(',', ':'))}")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "greet ok",
                "region": region,
                "sns_published": sns_publish_enabled,
            }
        ),
    }
