# --- Subnet Group for RDS ---
resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

# --- RDS Instance ---
resource "aws_db_instance" "default" {
  identifier             = "${var.project_name}-db"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0" # Or 5.7 depending on lab needs
  instance_class         = "db.t3.micro"
  db_name                = "studentrecords"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  multi_az               = false # Keep false for lab cost saving
}

# --- Secrets Manager ---
resource "aws_secretsmanager_secret" "db_creds" {
  name = "student-app-secret-${formatdate("YYYYMMDDhhmmss", timestamp())}" 
  # Timestamp added to ensure unique name if you re-run labs
}

resource "aws_secretsmanager_secret_version" "db_creds_val" {
  secret_id     = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.default.address
    dbname   = "studentrecords"
  })
}