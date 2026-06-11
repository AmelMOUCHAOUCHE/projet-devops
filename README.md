# Projet DevOps — Infrastructure Prism
**URL de l'application :** https://15-237-219-51.sslip.io
**Étudiantes :** Amel MOUCHAOUCHE & Olubusola ODUFEJO OGOE  
**Promotion :** 4e année EFREI  
**Repository :** https://github.com/AmelMOUCHAUOCHE/projet-devops

---

##Architecture


         Internet
            │
            ▼
    [ VM Load Balancer ] — Nginx + HTTPS (Let's Encrypt / sslip.io)
            │
            ├─────────────────────┐
            ▼                     ▼
      [ VM App 1 ]       [ VM App 2 ]   — Node.js backend + React frontend
        │                     │
        └──────────┬──────────┘
           ▼
     [ VM Database ]              — PostgreSQL (subnet privé)
           │
           ▼
      [ Bucket S3 ]               — Backups automatiques


## Machines AWS (région : eu-west-3 — Paris)

| Nom | Rôle | Type | Subnet | Ports ouverts |
|-----|------|------|--------|---------------|
| prism-lb | Load Balancer Nginx | t2.micro | Public | 80, 443 (Internet), 22 (admin) |
| prism-app-1 | Application | t2.micro | Public | 80, 3001 (LB uniquement), 22 (admin) |
| prism-app-2 | Application | t2.micro | Public | 80, 3001 (LB uniquement), 22 (admin) |
| prism-db | Base de données | t2.micro | **Privé** | 5432 (App uniquement), 22 (VPC) |

---

## Prérequis

- Terraform >= 1.5
- Ansible >= 2.21 + molecule + molecule-docker + ansible-lint
- AWS CLI configuré (région : eu-west-3)
- Docker (pour les tests Molecule)
- Python >= 3.10
- Clé SSH : `~/.ssh/id_rsa`

---

## Déploiement from scratch

### 1. Cloner le projet

```bash
git clone https://github.com/AmelMOUCHAUOCHE/projet-devops.git
cd projet-devops
```

### 2. Générer une clé SSH (si pas déjà fait)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### 3. Provisionner l'infrastructure avec Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Renseigner dans `terraform.tfvars` :
```hcl
my_ip               = "VOTRE_IP_PUBLIQUE/32"
ssh_public_key_path = "~/.ssh/id_rsa.pub"
```

> Pour connaître votre IP publique : `curl ifconfig.me`

```bash
terraform init
terraform plan
terraform apply
```

### 4. Générer l'inventaire Ansible automatiquement

```bash
cd ..
chmod +x generate_inventory.sh
./generate_inventory.sh
```

Le script lit les outputs Terraform et génère `ansible/inventory/hosts.yml` avec les IPs réelles des machines.

### 5. Configurer les secrets Ansible

```bash
cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml
nano ansible/group_vars/all/vault.yml
```

Renseigner :
```yaml
vault_db_password: "votre_mot_de_passe_db"
vault_github_token: "votre_token_github"
```

Puis chiffrer :
```bash
ansible-vault encrypt ansible/group_vars/all/vault.yml
```

### 6. Lancer le déploiement Ansible

```bash
cd ansible
ansible-playbook playbook.yml --ask-vault-pass
```

L'ordre d'exécution des rôles :
1. `database` — installation et configuration PostgreSQL
2. `application` — déploiement Node.js + React sur prism-app-1 et prism-app-2
3. `loadbalancer` — configuration Nginx + certificat HTTPS Let's Encrypt
4. `backup` — mise en place du cron de sauvegarde vers S3

---

## Stratégie de backup

| Paramètre | Valeur |
|-----------|--------|
| Outil | pg_dump |
| Format | `.sql.gz` (dump compressé) |
| Fréquence | Quotidienne à 02h00 |
| Rétention locale (prism-db) | 7 jours |
| Rétention S3 | 30 jours |
| Anciennes versions S3 | 7 jours |
| Destination S3 | `s3://prism-backups-xxxx/db/` |
| Authentification S3 | Rôle IAM attaché à la VM (aucune credential en clair) |

Les backups sont automatiquement uploadés vers le bucket S3 `prism-backups-xxxx` via un rôle IAM AWS attaché aux instances — aucun secret AWS n'est stocké sur les machines.

---

## Restauration depuis S3

```bash
ansible-playbook ansible/restore.yml --ask-vault-pass
```

Le playbook demande interactivement le nom du fichier à restaurer (ex: `prism_20260610_020000.sql.gz`), le télécharge depuis S3, recrée la base et restaure les données.

Pour lister les backups disponibles dans S3 :
```bash
aws s3 ls s3://prism-backups-xxxx/db/ --region eu-west-3
```

---

## Tests Molecule

Chaque rôle Ansible dispose d'un scénario Molecule avec le driver Docker.

```bash
# Tester le rôle application
cd ansible/roles/application && molecule test

# Tester le rôle database
cd ansible/roles/database && molecule test

# Tester le rôle loadbalancer
cd ansible/roles/loadbalancer && molecule test

# Tester le rôle backup
cd ansible/roles/backup && molecule test

# Tester tous les rôles d'un coup
for role in ansible/roles/*/; do
  echo "=== Testing $role ==="
  (cd "$role" && molecule test)
done
```

---

## Sécurité

- Secrets chiffrés avec **Ansible Vault** (`vault.yml`)
- `.tfstate`, `terraform.tfvars` et `vault.yml` exclus via `.gitignore`
- Accès SSH restreint à l'IP du déployeur via `my_ip` dans les security groups
- VM `prism-db` dans un **subnet privé** sans IP publique
- Bucket S3 entièrement privé avec chiffrement **AES256**
- Accès S3 via **rôle IAM** attaché aux instances (pas de clés AWS en dur)
