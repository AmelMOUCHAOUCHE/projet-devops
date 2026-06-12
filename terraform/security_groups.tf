# Security Group - Load Balancer
# Expose 80 et 443 sur internet
# SSH restreint à my_ip
resource "aws_security_group" "loadbalancer" {
  name = "${var.project_name}-lb-sg"
  description = "Security group du load balancer Nginx"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP depuis internet"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS depuis internet"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH pour Ansible"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Tout le trafic sortant autorise"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lb-sg"
    Project = var.project_name
  }
}


# Security Group - VMs pour les applications
# Accepte HTTP/API uniquement depuis le load balancer
# SSH restreint à my_ip
resource "aws_security_group" "app" {
  name = "${var.project_name}-app-sg"
  description = "Security group des VMs pour les applications"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP depuis le load balancer"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.loadbalancer.id]
  }

  ingress {
    description = "API backend (port 3001) depuis le load balancer"
    from_port = 3001
    to_port = 3001
    protocol = "tcp"
    security_groups = [aws_security_group.loadbalancer.id]
  }

  ingress {
    description = "SSH pour Ansible"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Tout le trafic sortant autorise"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}


# Security Group - Base de données
# PostgreSQL accessible uniquement depuis les VMs
# Pas d'accès HTTP/HTTPS depuis internet
# SSH restreint à my_ip (accès admin direct)
resource "aws_security_group" "database" {
  name = "${var.project_name}-db-sg"
  description = "Security group de la VM base de donnees"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "PostgreSQL depuis les VMs uniquement"
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description = "SSH via ProxyJump depuis les VMs applicatives"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Tout le trafic sortant autorise"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
    Project = var.project_name
  }
}


# Security Group - Usine logicielle (CI/CD)
# Jenkins, SonarQube, Nexus - isolé du réseau applicatif
resource "aws_security_group" "citools" {
  name        = "${var.project_name}-citools-sg"
  description = "Security group for CI/CD tools"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP pour certbot"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SonarQube"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Nexus"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH pour Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "All outbound traffic allowed"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-citools-sg"
    Project = var.project_name
  }
}
