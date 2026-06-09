locals {
  lambda_zip = "${path.module}/../../lambda/build/ingest.zip"
}

# ---------------------------------------------------------------------
# IAM da Lambda
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

# ENI na VPC (obrigatorio para Lambda em VPC)
resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissoes" {
  statement {
    sid       = "LerObjetosDoBucket"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.raw.arn}/*"]
  }
  statement {
    sid       = "EnviarFalhasParaDLQ"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
  # Metricas saem via EMF (linha de log) -> nao precisa de cloudwatch:PutMetricData.
}

# Fila de mensagens mortas: captura o evento S3 se a Lambda falhar apos as
# tentativas automaticas (envio feito pelo servico Lambda, funciona em VPC sem NAT).
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-ingestao-dlq"
  message_retention_seconds = 1209600 # 14 dias
  tags                      = { Name = "${var.project_name}-ingestao-dlq" }
}

resource "aws_iam_role_policy" "lambda_permissoes" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissoes.json
}

# ---------------------------------------------------------------------
# Log group (criado antes para controlar a retencao)
# ---------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-ingestao"
  retention_in_days = 14
}

# ---------------------------------------------------------------------
# Funcao Lambda  (rode ./build.ps1 ou ./build.sh ANTES do apply)
# ---------------------------------------------------------------------
resource "aws_lambda_function" "ingestao" {
  function_name = "${var.project_name}-ingestao"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "handler.lambda_handler"
  timeout       = 60
  memory_size   = 256

  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)

  vpc_config {
    subnet_ids         = aws_subnet.publica[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  environment {
    variables = {
      DB_HOST      = aws_db_instance.mysql.address
      DB_PORT      = tostring(aws_db_instance.mysql.port)
      DB_USER      = var.db_username
      DB_PASSWORD  = var.db_password
      DB_NAME      = var.db_name
      CW_NAMESPACE = "GSCloud/Ingestao"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.vpc,
    aws_cloudwatch_log_group.lambda,
  ]
}

resource "aws_lambda_permission" "permite_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestao.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw.arn
}

# ---------------------------------------------------------------------
# Alarme: dispara se alguma execucao tiver linha com erro.
# ---------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "erros_ingestao" {
  alarm_name          = "${var.project_name}-erros-ingestao"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "LinhasComErro"
  namespace           = "GSCloud/Ingestao"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Ha linhas com erro na ingestao de telemetria"
  treat_missing_data  = "notBreaching"
  dimensions = {
    Funcao = "ingestao-telemetria"
  }
}

# ---------------------------------------------------------------------
# Dashboard: reune a evidencia da automacao em um unico painel.
# ---------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "ingestao" {
  dashboard_name = "${var.project_name}-ingestao"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "Ingestao - linhas e arquivos (soma)"
          region  = var.aws_region
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [
            ["GSCloud/Ingestao", "LinhasInseridas", "Funcao", "ingestao-telemetria"],
            ["GSCloud/Ingestao", "ArquivosProcessados", "Funcao", "ingestao-telemetria"],
            ["GSCloud/Ingestao", "LinhasComErro", "Funcao", "ingestao-telemetria"]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "Duracao da ingestao (ms)"
          region  = var.aws_region
          stat    = "Average"
          view    = "timeSeries"
          metrics = [
            ["GSCloud/Ingestao", "DuracaoMs", "Funcao", "ingestao-telemetria"]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title   = "Lambda - invocacoes e erros"
          region  = var.aws_region
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestao.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.ingestao.function_name]
          ]
        }
      }
    ]
  })
}
