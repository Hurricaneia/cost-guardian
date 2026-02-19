locals {
  project_name = var.project_name
}

resource "random_id" "suffix" {
  byte_length = 4
}

############################
# KMS KEY (for S3 + SSM SecureString)
############################

resource "aws_kms_key" "cost_guardian" {
  description             = "KMS key for Cost Guardian encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "cost_guardian" {
  name          = "alias/${local.project_name}"
  target_key_id = aws_kms_key.cost_guardian.id
}

############################
# S3 BUCKET (reports)
############################

resource "aws_s3_bucket" "reports" {
  bucket = "${local.project_name}-reports-${random_id.suffix.hex}"
}


resource "aws_s3_bucket_lifecycle_configuration" "reports_lifecycle" {
    bucket = aws_s3_bucket.reports.id

    rule {
        id = "expire-old-reports"
        status = "Enabled"

        expiration {
            days = 30
        }

        filter {}
    }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Default bucket encryption = KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cost_guardian.arn
    }
  }
}

# Enforce that uploads MUST specify aws:kms
resource "aws_s3_bucket_policy" "reports" {
  bucket = aws_s3_bucket.reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.reports.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

############################
# SSM PARAMETER (Slack webhook secret)
############################

resource "aws_ssm_parameter" "slack_webhook" {
  name  = "/${local.project_name}/slack_webhook"
  type  = "SecureString"
  value = var.slack_webhook_url
  key_id = aws_kms_key.cost_guardian.arn
}

############################
# IAM ROLE FOR LAMBDA
############################

resource "aws_iam_role" "lambda_exec" {
  name = "${local.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

# Basic logging to CloudWatch
resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# App permissions: SSM secret, KMS, EC2 describe, S3 put
resource "aws_iam_policy" "lambda_app_access" {
  name = "${local.project_name}-app-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read slack webhook from SSM
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.slack_webhook.arn
      },

      # Use KMS for decrypting SecureString + encrypting S3 objects
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.cost_guardian.arn
      },

      # Scan account resources (read-only)
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeRegions",
          "ec2:DescribeVolumes",
          "ec2:DescribeAddresses"
        ]
        Resource = "*"
      },

      # Write reports to S3
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.reports.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_app_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_app_access.arn
}

############################
# LAMBDA FUNCTION
############################
# IMPORTANT:
# This expects your zip to contain:
#   cost_guardian/handler.py
# and handler function:
#   lambda_handler(event, context)
#
# So handler string is:
#   cost_guardian.handler.lambda_handler
############################

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
      SLACK_PARAM   = aws_ssm_parameter.slack_webhook.name
      REPORT_BUCKET = aws_s3_bucket.reports.bucket
      KMS_KEY_ID    = aws_kms_key.cost_guardian.arn
    }
  }
}

############################
# EVENTBRIDGE SCHEDULE (daily)
############################

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${local.project_name}-daily"
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

############################
# GITHUB OIDC PROVIDER
############################

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

##################################
# GITHUB DEPLOY ROLE
##################################

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

###############################
# GITHUB IAM POLICY
###############################

resource "aws_iam_role_policy_attachment" "github_custom_attach" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}
resource "aws_iam_policy" "github_terraform_policy" {
    name = "cost-guardian-github-terraform-policy"

    policy = jsonencode ({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow",
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

###############################
# TERRAFORM REMOTE
###############################

resource "aws_s3_bucket" "tf_state" {
    bucket = "cost-guardian-tf-state-894943009636"

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
    name = "cost-guardian-tf-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
}
