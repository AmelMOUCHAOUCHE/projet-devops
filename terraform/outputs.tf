output "lb_public_ip" {
  description = "IP publique du load balancer"
  value = aws_instance.loadbalancer.public_ip
}

output "app_public_ips" {
  description = "IPs publiques des VMs applicatives"
  value = aws_instance.app[*].public_ip
}

output "db_public_ip" {
  description = "IP publique de la VM base de données"
  value = aws_instance.database.public_ip
}

output "db_private_ip" {
  description = "IP privée de la VM base de données"
  value = aws_instance.database.private_ip
}

output "s3_bucket_name" {
  description = "Nom du bucket S3 pour les backups"
  value = aws_s3_bucket.backups.bucket
}

output "s3_bucket_arn" {
  description = "ARN du bucket S3"
  value = aws_s3_bucket.backups.arn
}

output "iam_instance_profile_name" {
  description = "Nom du profil IAM à attacher aux instances pour l'accès S3"
  value = aws_iam_instance_profile.backup_profile.name
}

output "aws_region" {
  description = "Région AWS du déploiement"
  value = var.aws_region
}
