variable "aws_region" {
  description = "Région AWS"
  type = string
  default = "eu-west-3"
}

variable "project_name" {
  description = "Préfixe utilisé pour nommer toutes les ressources"
  type = string
  default = "prism"
}

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC"
  type = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Plage d'adresses du sous-réseau public"
  type = string
  default = "10.0.1.0/24"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type = string
  default = "t2.micro"
}

variable "app_count" {
  description = "Nombre de VMs applicatives"
  type = number
  default = 2
}

variable "ssh_public_key_path" {
  description = "Chemin vers clé SSH publique"
  type = string
  default = "~/.ssh/id_rsa.pub"
}

variable "my_ip" {
  description = "IP publique pour l'accès SSH (format : x.x.x.x/32)"
  type = string
}

variable "citools_instance_type" {
  description = "Type d'instance EC2 pour l'usine logicielle (Jenkins+SonarQube+Nexus)"
  type        = string
  default     = "t3.micro"
}

variable "private_subnet_cidr" {
  description = "Plage d'adresses du sous-réseau privé (DB)"
  type        = string
  default     = "10.0.2.0/24"
}
