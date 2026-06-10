# Suffixe aléatoire pour garantir l'unicité globale du nom de bucket
resource "random_id" "bucket_suffix" {
  byte_length = 4
}


# Bucket S3 - Stockage des backups
resource "aws_s3_bucket" "backups" {
  bucket = "${var.project_name}-backups-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-backups"
    Project = var.project_name
  }
}

# Bloquer tout accès public
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# Versioning activé : permet de récupérer une version antérieure d'un backup
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Politique de rétention :
# - Backups courants conservés 30 jours
# - Anciennes versions supprimées après 7 jours
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id = "backup-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Chiffrement des données au repos
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# IAM - Rôle pour les VMs (accès S3 en écriture)
# Les VMs application et DB VM utilisent ce rôle pour uploader les backups vers S3 sans credentials en clair
resource "aws_iam_role" "backup_role" {
  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "backup_s3_policy" {
  name = "${var.project_name}-backup-s3-policy"
  role = aws_iam_role.backup_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backup_profile" {
  name = "${var.project_name}-backup-profile"
  role = aws_iam_role.backup_role.name
}
