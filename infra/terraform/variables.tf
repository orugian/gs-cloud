variable "aws_region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo de nome dos recursos"
  type        = string
  default     = "gs-cloud"
}

variable "bucket_name" {
  description = "Nome GLOBALMENTE UNICO do bucket S3 (ex: gs-cloud-aero-<seunome>)"
  type        = string
}

variable "db_name" {
  description = "Nome do schema/banco inicial"
  type        = string
  default     = "aeroespacial"
}

variable "db_username" {
  description = "Usuario master do RDS"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Senha master do RDS (use terraform.tfvars, nao commite)"
  type        = string
  sensitive   = true
}

variable "my_ip_cidr" {
  description = "Seu IP publico em /32 para liberar o MySQL Workbench (ex: 200.1.2.3/32)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.20.0.0/16"
}
