# Projet DevOps – Déploiement de l'application Prism sur AWS

**Prism** est une application de planning personnel (gestion de médias, calendrier, repas, apprentissage des langues) composée de deux dépôts :
- un **frontend** React 19 / TypeScript / Vite, buildé puis servi statiquement par nginx sur chaque VM applicative ;
- un **backend** Express / Prisma (architecture MVC) tournant sous PM2 sur le port 3001, avec PostgreSQL comme base de données - nginx proxifie `/api` vers le backend.

Ce dépôt contient **l'infrastructure de déploiement** de Prism sur AWS : provisionnement en infrastructure-as-code (Terraform), configuration et déploiement automatisés (Ansible), sauvegarde quotidienne de la base vers S3, HTTPS sur tous les points d'entrée, et une usine logicielle dédiée (Jenkins + SonarQube + Nexus).

---

## Architecture

```
                         Internet
                            │
                    ┌───────▼────────┐
                    │  Load Balancer │  t2.micro - sous-réseau public
                    │  nginx + HTTPS │  ports entrants : 80, 443
                    └───────┬────────┘
              ┌─────────────┴─────────────┐
              │ :80 / :3001               │ :80 / :3001
      ┌───────▼───────┐           ┌───────▼───────┐
      │    App VM 1   │           │    App VM 2   │  t2.micro
      │  Node.js/PM2  │           │  Node.js/PM2  │  port entrant : 80, 3001 (LB seulement)
      │  nginx proxy  │           │  nginx proxy  │
      └───────┬───────┘           └───────┬───────┘
              └─────────────┬─────────────┘
                            │ :5432 (app SG seulement)
                    ┌───────▼────────┐
                    │  Database VM   │  t2.micro - SG restreint aux App VMs
                    │  PostgreSQL    │  SSH uniquement via ProxyJump depuis App VMs
                    └───────┬────────┘
                            │ pg_dump quotidien
                    ┌───────▼────────┐
                    │   AWS S3       │  stockage des backups chiffrés
                    └────────────────┘

                    ┌────────────────────────────────────┐
                    │         CI Tools VM  (bonus)        │  t3.micro - sous-réseau public
                    │  Jenkins   :8080 → HTTPS :443       │  ports : 80, 443, 8080, 9000, 8081
                    │  SonarQube :9000 → HTTPS :443       │  isolée du réseau applicatif
                    │  Nexus     :8081 → HTTPS :443       │
                    └────────────────────────────────────┘
```

**Flux réseau :**
- Internet → LB (80/443) → App VMs (80/3001) → DB (5432)
- Le LB n'a aucun accès à la DB (security groups distincts)
- La DB est en sous-réseau privé, SSH uniquement via ProxyJump depuis les App VMs
- La VM citools n'a aucune règle vers le réseau applicatif ni la DB

---

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.14
- [Molecule](https://ansible.readthedocs.io/projects/molecule/) + `molecule-plugins[docker]` (tests)
- AWS CLI configuré (`aws configure`) avec droits EC2, VPC, S3, IAM
- Une paire de clés SSH (`~/.ssh/id_rsa` / `id_rsa.pub`)

---

## Déploiement complet

### 1. Cloner le dépôt

```bash
git clone <url-du-repo>
cd projet-devops
```

### 2. Configurer les credentials AWS

Terraform et le script d'inventaire utilisent les credentials du CLI AWS :

```bash
aws configure
```

Renseigner l'Access Key ID et la Secret Access Key d'un compte IAM disposant des droits EC2, VPC, S3 et IAM, et la région `eu-west-3`.

### 3. Configurer Terraform

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Éditer `terraform/terraform.tfvars` :

```hcl
my_ip               = "X.X.X.X/32"        # IP publique (curl ifconfig.me)
ssh_public_key_path = "~/.ssh/id_rsa.pub"
```

### 4. Déployer l'infrastructure

```bash
cd terraform
terraform init
terraform apply
cd ..
```

Vérifier que toutes les instances sont `running` avant de continuer :

```bash
aws ec2 describe-instances --region eu-west-3 \
  --filters "Name=tag:Project,Values=prism" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,State.Name]" --output table
```

### 5. Générer l'inventaire Ansible

```bash
chmod +x generate_inventory.sh
./generate_inventory.sh
```

Le script lit les outputs Terraform et génère `ansible/inventory/hosts.yml`

### 6. Configurer les secrets (Ansible Vault)

```bash
cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml
```

Éditer `ansible/group_vars/all/vault.yml` - remplacer toutes les valeurs `change_me` :

```yaml
vault_db_password: "mot_de_passe_choisi"
vault_database_url: "postgresql://prism:mot_de_passe_choisi@<DB_PRIVATE_IP>:5432/prism"
vault_github_token: "ghp_xxxxxxxxxxxx"   # token fourni par mail
```

Chiffrer le fichier :

```bash
ansible-vault encrypt ansible/group_vars/all/vault.yml
echo "votre_mot_de_passe_vault" > .vault_pass
```

### 7. Installer les collections Ansible

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cd ..
```

### 8. Déployer l'application

```bash
cd ansible
ansible-playbook playbook.yml --vault-password-file ../.vault_pass
```

Ce playbook configure dans l'ordre :
1. **Database** - PostgreSQL, création du rôle et de la base, migrations Prisma
2. **Application** - Node.js, PM2, nginx (×2 VMs)
3. **Load Balancer** - nginx, HTTPS Let's Encrypt
4. **Backup** - script cron + upload S3
5. **CI Tools** - Jenkins, SonarQube, Nexus, HTTPS via sslip.io *(bonus)*

---

## Stratégie de backup

Les backups sont réalisés via `pg_dump` et stockés dans le bucket S3.

| Paramètre     | Valeur                                  |
|---------------|-----------------------------------------|
| Fréquence     | Quotidienne à 02h00 UTC                 |
| Rétention     | 7 jours (fichiers locaux supprimés après) |
| Localisation  | `s3://<bucket>/db/`                     |
| Format        | `prism_YYYYMMDD_HHMMSS.sql.gz` (dump PostgreSQL compressé) |

Les fichiers S3 sont conservés sans limite de durée (pas de lifecycle rule). Pour lister les backups disponibles :

```bash
aws s3 ls s3://$(cd terraform && terraform output -raw s3_bucket_name)/db/ --region eu-west-3
```

---

## Restauration depuis S3

Playbook dédié, exécutable indépendamment du playbook principal :

```bash
cd ansible
ansible-playbook restore.yml --vault-password-file ../.vault_pass
```

Le playbook demande interactivement le fichier à restaurer :

```
Nom du fichier backup S3 à restaurer (ex: prism_20260610_020000.sql.gz):
```

**Ce que fait le playbook :**
1. Télécharge le fichier depuis S3 vers `/opt/backups/` sur la VM database
2. Supprime la base existante et la recrée
3. Restaure depuis le dump compressé
4. Supprime le fichier local après restauration

---

## Usine logicielle - Jenkins + SonarQube + Nexus *(bonus)*

La VM `citools` (t3.micro) héberge Jenkins, SonarQube et Nexus avec HTTPS automatique via [sslip.io](https://sslip.io). Elle est isolée du réseau applicatif (security group dédié, aucune règle croisée).

| Service    | URL                                      |
|------------|------------------------------------------|
| Jenkins    | `https://jenkins.<IP-citools>.sslip.io`  |
| SonarQube  | `https://sonar.<IP-citools>.sslip.io`    |
| Nexus      | `https://nexus.<IP-citools>.sslip.io`    |

L'IP citools : `terraform output citools_public_ip` ou affichée par `./generate_inventory.sh`.

**Cohabitation des versions Java** (chaque outil a des exigences incompatibles) :

| Outil | Java requis | Mécanisme |
|-------|-------------|-----------|
| Jenkins >= 2.463 | 21 | Drop-in systemd (`ExecStart` explicite) |
| SonarQube 10.x | 17 | Défaut système via `update-alternatives` |
| Nexus 3.70.x | 8 | `INSTALL4J_JAVA_HOME_OVERRIDE` dans `bin/nexus` |

**Autres choix techniques :**
- 4 Go de swap ajoutés automatiquement (3 JVM sur t3.micro 1 Go RAM)
- Heap Nexus réduit de 2703m à 512m (`nexus.vmoptions`)

**Premier accès** (mots de passe initiaux, à récupérer en SSH sur la VM citools) :

| Outil | Identifiants initiaux |
|-------|----------------------|
| Jenkins | `sudo cat /var/lib/jenkins/secrets/initialAdminPassword` |
| SonarQube | `admin` / `admin` |
| Nexus | `admin` / `sudo cat /opt/sonatype-work/nexus3/admin.password` |

---

## Tests Molecule

Chaque rôle Ansible dispose de tests Molecule exécutables localement avec Docker.

```bash
cd ansible/roles/jenkins     && molecule test && cd ../..
cd ansible/roles/sonarqube   && molecule test && cd ../..
cd ansible/roles/nexus       && molecule test && cd ../..
cd ansible/roles/application && molecule test && cd ../..
cd ansible/roles/database    && molecule test && cd ../..
cd ansible/roles/loadbalancer && molecule test && cd ../..
cd ansible/roles/backup      && molecule test && cd ../..
```

---

## Structure du projet

```
├── terraform/
│   ├── main.tf                   # VPC, subnets, IGW, routage
│   ├── instances.tf              # EC2 (LB, app×2, DB, citools)
│   ├── security_groups.tf        # Règles pare-feu par rôle
│   ├── outputs.tf                # IPs exportées pour generate_inventory.sh
│   ├── variables.tf              # Variables (région, types d'instance…)
│   ├── s3.tf                     # Bucket S3 pour les backups
│   └── terraform.tfvars.example  # Template de configuration
│
├── ansible/
│   ├── playbook.yml              # Orchestration complète (DB → App → LB → Backup → CI)
│   ├── restore.yml               # Restauration base de données depuis S3
│   ├── requirements.yml          # Collections Galaxy requises
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml.example     # Template d'inventaire
│   ├── group_vars/all/
│   │   ├── vars.yml              # Variables non sensibles
│   │   └── vault.yml.example     # Template des secrets (à chiffrer avec Vault)
│   └── roles/
│       ├── database/             # PostgreSQL + migrations
│       ├── application/          # Node.js + PM2 + nginx
│       ├── loadbalancer/         # nginx + HTTPS Let's Encrypt
│       ├── backup/               # Sauvegarde PostgreSQL → S3
│       ├── jenkins/              # Jenkins (Java 21, nginx, HTTPS) + Molecule
│       ├── sonarqube/            # SonarQube (Java 17, nginx, HTTPS) + Molecule
│       └── nexus/                # Nexus (Java 8, nginx, HTTPS) + Molecule
│
└── generate_inventory.sh         # Génère hosts.yml depuis les outputs Terraform
```

---

## Sécurité

Aucune credential n'est commitée en clair :

| Donnée sensible | Mécanisme de protection |
|-----------------|------------------------|
| Mots de passe, tokens | Ansible Vault (`vault.yml`, exclu du git) |
| IPs personnelles | `terraform.tfvars` exclu du git |
| État Terraform | `terraform.tfstate` exclu du git |
| Clés SSH | `*.pem`, `*.ppk` exclus du git |
