# AMI - Ubuntu 22.04 LTS (Jammy)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"]

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}


# Paire de clés SSH
resource "aws_key_pair" "prism" {
  key_name = "${var.project_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Project = var.project_name
  }
}


# VM Load Balancer (Nginx)
resource "aws_instance" "loadbalancer" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.loadbalancer.id]
  key_name = aws_key_pair.prism.key_name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-lb"
    Role = "loadbalancer"
    Project = var.project_name
  }
}


# VMs applicatives (back Node.js + front)
# Deux instances identiques derrière le load balancer
resource "aws_instance" "app" {
  count = var.app_count
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name = aws_key_pair.prism.key_name
  iam_instance_profile = aws_iam_instance_profile.backup_profile.name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-app-${count.index + 1}"
    Role = "app"
    Project = var.project_name
  }
}


# VM Usine logicielle (Jenkins + SonarQube)
resource "aws_instance" "citools" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.citools_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.citools.id]
  key_name               = aws_key_pair.prism.key_name

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-citools"
    Role = "citools"
    Project = var.project_name
  }
}


# VM Base de données (PostgreSQL)
resource "aws_instance" "database" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.database.id]
  key_name = aws_key_pair.prism.key_name
  iam_instance_profile = aws_iam_instance_profile.backup_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-db"
    Role = "database"
    Project = var.project_name
  }
}
