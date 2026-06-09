resource "aws_db_subnet_group" "principal" {
  name       = "${var.project_name}-subnet-group"
  subnet_ids = aws_subnet.publica[*].id
  tags       = { Name = "${var.project_name}-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier     = "${var.project_name}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro" # Free Tier

  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.principal.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true # necessario para o MySQL Workbench conectar

  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0

  tags = { Name = "${var.project_name}-mysql" }
}
