#!/usr/bin/env bash
# generate_inventory.sh
# Génère ansible/inventory/hosts.yml depuis les outputs Terraform.
# À lancer depuis la racine du projet après terraform apply.
#
# Usage : ./generate_inventory.sh

set -euo pipefail

TERRAFORM_DIR="$(dirname "$0")/terraform"
INVENTORY_FILE="$(dirname "$0")/ansible/inventory/hosts.yml"

echo "Lecture des outputs Terraform..."
cd "$TERRAFORM_DIR"

LB_IP=$(terraform output -raw lb_public_ip)
DB_PRIVATE_IP=$(terraform output -raw db_private_ip)
CITOOLS_IP=$(terraform output -raw citools_public_ip)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
AWS_REGION=$(terraform output -raw aws_region)
SSH_PRIVATE_KEY=$(terraform output -raw ssh_private_key_path)

# Récupérer les IPs des VMs app (tableau JSON)
APP_IPS_JSON=$(terraform output -json app_public_ips)
APP_IP_1=$(echo "$APP_IPS_JSON" | python3 -c "import sys,json; ips=json.load(sys.stdin); print(ips[0])")
APP_IP_2=$(echo "$APP_IPS_JSON" | python3 -c "import sys,json; ips=json.load(sys.stdin); print(ips[1])")

APP_PRIVATE_IPS_JSON=$(terraform output -json app_private_ips)
APP_PRIVATE_IP_1=$(echo "$APP_PRIVATE_IPS_JSON" | python3 -c "import sys,json; ips=json.load(sys.stdin); print(ips[0])")
APP_PRIVATE_IP_2=$(echo "$APP_PRIVATE_IPS_JSON" | python3 -c "import sys,json; ips=json.load(sys.stdin); print(ips[1])")

cd - > /dev/null

echo "Génération de $INVENTORY_FILE..."

cat > "$INVENTORY_FILE" <<EOF
# Inventaire Ansible généré automatiquement par generate_inventory.sh
# Ne pas modifier manuellement - relancer le script après terraform apply

all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY}
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
    s3_bucket_name: "${S3_BUCKET}"
    aws_region: "${AWS_REGION}"
    db_private_ip: "${DB_PRIVATE_IP}"

loadbalancer:
  hosts:
    lb:
      ansible_host: ${LB_IP}

app:
  hosts:
    app-1:
      ansible_host: ${APP_IP_1}
      private_ip: ${APP_PRIVATE_IP_1}
    app-2:
      ansible_host: ${APP_IP_2}
      private_ip: ${APP_PRIVATE_IP_2}

database:
  hosts:
    db:
      ansible_host: ${DB_PRIVATE_IP}
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand='ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_PRIVATE_KEY} ubuntu@${APP_IP_1}'"

citools:
  hosts:
    citools:
      ansible_host: ${CITOOLS_IP}
EOF

echo "Inventaire généré avec succès :"
echo "  Load Balancer : ${LB_IP}"
echo "  App 1         : ${APP_IP_1}"
echo "  App 2         : ${APP_IP_2}"
echo "  Database      : ${DB_PRIVATE_IP} (privée, via ProxyJump ${APP_IP_1})"
echo "  CI Tools      : ${CITOOLS_IP}"
echo "  S3 Bucket     : ${S3_BUCKET}"
