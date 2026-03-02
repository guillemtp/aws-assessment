locals {
  name_prefix               = "${var.project_name}-${var.region_name}"
  sns_publish_enabled_value = tostring(var.sns_publish_enabled)
}

resource "aws_dynamodb_table" "greeting_logs" {
  name         = "${local.name_prefix}-greeting-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }
}

resource "aws_iam_role" "greeter_lambda" {
  name = "${local.name_prefix}-greeter-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "greeter_lambda" {
  name = "${local.name_prefix}-greeter-lambda-policy"
  role = aws_iam_role.greeter_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["dynamodb:PutItem"]
          Resource = aws_dynamodb_table.greeting_logs.arn
        }
      ],
      var.sns_publish_enabled ? [
        {
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = var.verification_topic_arn
        }
      ] : []
    )
  })
}

data "archive_file" "greeter_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/greeter/handler.py"
  output_path = "${path.module}/greeter.zip"
}

resource "aws_lambda_function" "greeter" {
  function_name    = "${local.name_prefix}-greeter"
  role             = aws_iam_role.greeter_lambda.arn
  runtime          = "python3.11"
  handler          = "handler.handler"
  filename         = data.archive_file.greeter_zip.output_path
  source_code_hash = data.archive_file.greeter_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME             = aws_dynamodb_table.greeting_logs.name
      CANDIDATE_EMAIL        = var.candidate_email
      REPO_URL               = var.repo_url
      VERIFICATION_TOPIC_ARN = var.verification_topic_arn
      SNS_PUBLISH_ENABLED    = local.sns_publish_enabled_value
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}-public-a"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs_task" {
  name        = "${local.name_prefix}-ecs-task-sg"
  description = "Allow egress for ECS task"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}-publisher"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  count = var.sns_publish_enabled ? 1 : 0

  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = var.verification_topic_arn
    }]
  })
}

resource "aws_ecs_task_definition" "publisher" {
  family                   = "${local.name_prefix}-publisher"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "sns-publisher"
      image = "public.ecr.aws/aws-cli/aws-cli:2.17.52"
      command = [
        "/bin/sh",
        "-c",
        "if [ \"$SNS_PUBLISH_ENABLED\" = \"true\" ]; then PAYLOAD=$(printf '{\\\"email\\\":\\\"%s\\\",\\\"source\\\":\\\"ECS\\\",\\\"region\\\":\\\"%s\\\",\\\"repo\\\":\\\"%s\\\"}' \"$EMAIL\" \"$EXEC_REGION\" \"$REPO_URL\"); aws sns publish --topic-arn \"$TOPIC_ARN\" --message \"$PAYLOAD\" --region \"$EXEC_REGION\"; else echo \"SNS dry run enabled - skipping publish\"; fi"
      ]
      essential = true
      environment = [
        { name = "EMAIL", value = var.candidate_email },
        { name = "REPO_URL", value = var.repo_url },
        { name = "TOPIC_ARN", value = var.verification_topic_arn },
        { name = "EXEC_REGION", value = var.region_name },
        { name = "SNS_PUBLISH_ENABLED", value = local.sns_publish_enabled_value }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region_name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_iam_role" "dispatcher_lambda" {
  name = "${local.name_prefix}-dispatcher-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "dispatcher_lambda" {
  name = "${local.name_prefix}-dispatcher-lambda-policy"
  role = aws_iam_role.dispatcher_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [
          aws_ecs_task_definition.publisher.arn,
          aws_ecs_task_definition.publisher.arn_without_revision
        ]
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "dispatcher_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/dispatcher/handler.py"
  output_path = "${path.module}/dispatcher.zip"
}

resource "aws_lambda_function" "dispatcher" {
  function_name    = "${local.name_prefix}-dispatcher"
  role             = aws_iam_role.dispatcher_lambda.arn
  runtime          = "python3.11"
  handler          = "handler.handler"
  filename         = data.archive_file.dispatcher_zip.output_path
  source_code_hash = data.archive_file.dispatcher_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ECS_CLUSTER_ARN     = aws_ecs_cluster.this.arn
      TASK_DEFINITION_ARN = aws_ecs_task_definition.publisher.arn
      SUBNET_IDS          = aws_subnet.public_a.id
      SECURITY_GROUP_IDS  = aws_security_group.ecs_task.id
      SNS_PUBLISH_ENABLED = local.sns_publish_enabled_value
    }
  }
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "${local.name_prefix}-cognito-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_user_client_id]
    issuer   = var.cognito_issuer
  }
}

resource "aws_apigatewayv2_integration" "greeter" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatcher" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "greet" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /greet"
  target             = "integrations/${aws_apigatewayv2_integration.greeter.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /dispatch"
  target             = "integrations/${aws_apigatewayv2_integration.dispatcher.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_greeter_from_apigw" {
  statement_id  = "AllowExecutionFromAPIGatewayGreeter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_dispatcher_from_apigw" {
  statement_id  = "AllowExecutionFromAPIGatewayDispatcher"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
