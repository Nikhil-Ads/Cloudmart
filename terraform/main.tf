terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}


provider "aws" {
  region = "us-east-1"
}

provider "time" {}

# Tables DynamoDB
resource "aws_dynamodb_table" "cloudmart_products" {
  name           = "cloudmart-products"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "cloudmart_orders" {
  name           = "cloudmart-orders"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

resource "aws_dynamodb_table" "cloudmart_tickets" {
  name           = "cloudmart-tickets"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "cloudmart_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "cloudmart_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_dynamodb_table.cloudmart_products.arn,
          aws_dynamodb_table.cloudmart_orders.arn,
          "${aws_dynamodb_table.cloudmart_orders.arn}/stream/*",
          aws_dynamodb_table.cloudmart_tickets.arn,
          "arn:aws:logs:*:*:*"
        ]
      }
    ]
  })
}

# Lambda function for listing products
resource "aws_lambda_function" "list_products" {
  filename         = "list_products.zip"
  function_name    = "cloudmart-list-products"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = filebase64sha256("list_products.zip")

  environment {
    variables = {
      PRODUCTS_TABLE = aws_dynamodb_table.cloudmart_products.name
    }
  }
}

# Lambda permission for Bedrock
resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_products.function_name
  principal     = "bedrock.amazonaws.com"
}

# Output the ARN of the Lambda function
output "list_products_function_arn" {
  value = aws_lambda_function.list_products.arn
}

# Lambda function for DynamoDB to BigQuery
resource "aws_lambda_function" "dynamodb_to_bigquery" {
  filename         = "../backend/src/lambda/addToBigQuery/dynamodb_to_bigquery.zip"
  function_name    = "cloudmart-dynamodb-to-bigquery"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = filebase64sha256("../backend/src/lambda/addToBigQuery/dynamodb_to_bigquery.zip")

  environment {
    variables = {
      GOOGLE_CLOUD_PROJECT_ID        = "my-project-cloudmart"
      BIGQUERY_DATASET_ID            = "cloudmart"
      BIGQUERY_TABLE_ID              = "cloudmart-orders"
      GOOGLE_APPLICATION_CREDENTIALS = "/var/task/google_credentials.json"
    }
  }
}

# Lambda event source mapping for DynamoDB stream
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = aws_dynamodb_table.cloudmart_orders.stream_arn
  function_name     = aws_lambda_function.dynamodb_to_bigquery.arn
  starting_position = "LATEST"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "bedrock_agent_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["bedrock.amazonaws.com"]
      type        = "Service"
    }
    condition {
      test     = "StringEquals"
      values   = [data.aws_caller_identity.current.account_id]
      variable = "aws:SourceAccount"
    }
    condition {
      test     = "ArnLike"
      values   = ["arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent/*"]
      variable = "AWS:SourceArn"
    }
  }
}

data "aws_iam_policy_document" "bedrock_model_invoke" {
  statement {
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
    ]
  }
}

# Create IAM role for Bedrock Agent
resource "aws_iam_role" "bedrock_agent_role" {
  name = "bedrock-agent-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_agent_trust.json
}

resource "aws_iam_role_policy" "bedrock_model_invoke_policy" {
  policy = data.aws_iam_policy_document.bedrock_model_invoke.json
  role   = aws_iam_role.bedrock_agent_role.name
  name = "BedrockModelAccessPolicy"
}


# Create IAM policy to Invoke Lambda function
resource "aws_iam_policy" "access_lambda_policy" {
  name        = "LambdaAccessPolicy"
  path        = "/"
  description = "IAM policy for accessing Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement =  [
        {
            Effect = "Allow",
            Action = "lambda:InvokeFunction",
            Resource = "arn:aws:lambda:*:*:function:cloudmart-list-products"
        },
        {
            Effect = "Allow",
            Action = "bedrock:InvokeModel",
            Resource = "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
        }
    ]
  })
}

# Attach the Bedrock model access policy to the Bedrock Agent role
resource "aws_iam_role_policy_attachment" "access_bedrock_policy_attachment" {
  policy_arn = aws_iam_policy.access_lambda_policy.arn
  role       = aws_iam_role.bedrock_agent_role.name
}

# Create AWS Bedrock Agent
resource "aws_bedrockagent_agent" "cloudmart_agent" {
  agent_name    = "cloudmart-product-recommendation-agent"
  instruction   = file("${path.module}/../res/agent_instructions.txt")
  description   = "AI agent to assist CloudMart customers"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn

  foundation_model = "anthropic.claude-3-sonnet-20240229-v1:0"

}

resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
}

# Associate the Lambda function with the Bedrock Agent
resource "aws_bedrockagent_agent_action_group" "cloudmart_action_group" {
  agent_id           = aws_bedrockagent_agent.cloudmart_agent.id
  agent_version      = "DRAFT"
  action_group_name  = "Get-Product-Recommendations"
  description        = "Action group for CloudMart operations"
  skip_resource_in_use_check = true

  action_group_executor {
    lambda = aws_lambda_function.list_products.arn
  }

  action_group_state = "ENABLED"

  depends_on = [time_sleep.wait_30_seconds]

  api_schema {
    payload = file("${path.module}/../res/product_schema.json")
  }
  prepare_agent = true
}

# Create an alias for the Bedrock Agent
resource "aws_bedrockagent_agent_alias" "cloudmart_agent_alias" {
  agent_id    = aws_bedrockagent_agent.cloudmart_agent.id
  depends_on = [aws_bedrockagent_agent_action_group.cloudmart_action_group]
  agent_alias_name = "cloudmart-prod"
}
