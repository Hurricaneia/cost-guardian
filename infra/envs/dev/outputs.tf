output "bucket_name" {
	value = aws_s3_bucket.reports.bucket
}

output "lambda_name" {
	value= aws_lambda_function.cost_guardian.function_name
}

output "kms_key_id" {
	value = aws_kms_key.cost_guardian.id
}
