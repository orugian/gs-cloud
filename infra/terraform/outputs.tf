output "bucket_nome" {
  description = "Bucket onde subir os arquivos .csv"
  value       = aws_s3_bucket.raw.bucket
}

output "rds_endpoint" {
  description = "Host do RDS para o MySQL Workbench"
  value       = aws_db_instance.mysql.address
}

output "rds_porta" {
  value = aws_db_instance.mysql.port
}

output "lambda_nome" {
  value = aws_lambda_function.ingestao.function_name
}

output "log_group" {
  description = "Onde ver os logs da ingestao no CloudWatch"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "dashboard" {
  description = "Nome do dashboard de evidencias no CloudWatch"
  value       = aws_cloudwatch_dashboard.ingestao.dashboard_name
}

output "dlq_url" {
  description = "Fila SQS que captura arquivos que falharam na ingestao"
  value       = aws_sqs_queue.dlq.url
}
