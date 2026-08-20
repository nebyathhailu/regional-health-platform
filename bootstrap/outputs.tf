output "state_bucket" {
  description = "S3 bucket name -- use as the `bucket` value in every individual repo's `-backend-config`."
  value       = aws_s3_bucket.tfstate.bucket
}

output "lock_table" {
  description = "DynamoDB table name -- use as the `dynamodb_table` value in every individual repo's `-backend-config`."
  value       = aws_dynamodb_table.tflock.name
}
