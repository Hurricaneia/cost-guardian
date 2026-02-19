
data "aws_caller_identity" "current" {}

locals {
  project_name = "cost-guardian"
}

# ================================
# KMS Key
# ================================

resource "aws_kms_key" "cost_guardian" {
  description             = "KMS key for Cost Guardian"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "cost_guardian" {
  name          = "alias/cost-guardian"
  target_key_id = aws_kms_key.cost_guardian.key_id
}

# ================================
# Reports S3 Bucket
# ================================

resource "aws_s3_bucket" "reports" {
  bucket = "cost-guardian-reports-6961f213"
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cost_guardian.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports_lifecycle" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-old-reports"
    status = "Enabled"

    expiration {
      days = 30
    }

    filter {}
  }
}

# ================================
# SSM Slack Parameter
# ================================

resource "aws_ssm_parameter" "slack_webhook" {
  name   = "/cost-guardian/slack_webhook"
  type   = "SecureString"
  value  = "REPLACE_ME"
  key_id = aws_kms_key.cost_guardian.arn
}

# ================================
# Lambda IAM Role
# ================================

resource "aws_iam_role" "lambda_exec" {
  name = "cost-guardian-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_custom_policy" {
  name = "cost-guardian-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ssm:GetParameter",
          "kms:Decrypt",
          "s3:PutObject",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
	{
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:Encrypt"
        ]
        Resource = aws_kms_key.cost_guardian.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}

# ================================
# Lambda Function
# ================================

resource "aws_lambda_function" "cost_guardian" {
  function_name = local.project_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "cost_guardian.handler.lambda_handler"
  runtime       = "python3.11"

  filename         = "${path.module}/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")

  timeout     = 60
  memory_size = 512

  environment {
    variables = {
      SLACK_PARAM  = aws_ssm_parameter.slack_webhook.name
      REPORT_BUCKET = aws_s3_bucket.reports.bucket
    }
  }
}

# ================================
# EventBridge Schedule
# ================================

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "cost-guardian-daily"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily.name
  target_id = "cost_guardian_lambda"
  arn       = aws_lambda_function.cost_guardian.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_guardian.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}

# ================================
# Terraform Remote State Backend Infrastructure
# ================================

resource "aws_s3_bucket" "tf_state" {
  bucket = "cost-guardian-tf-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_encryption" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "cost-guardian-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ================================
# GitHub OIDC Provider
# ================================

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

resource "aws_iam_role" "github_actions_role" {
  name = "cost-guardian-github-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Hurricaneia/cost-guardian:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_terraform_policy" {
  name = "cost-guardian-github-terraform-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:*",
          "iam:*",
          "s3:*",
          "dynamodb:*",
          "kms:*",
          "events:*",
          "ssm:*",
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_custom_attach" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}

