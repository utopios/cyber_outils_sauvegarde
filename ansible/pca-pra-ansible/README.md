# PCA/PRA Ansible - FinSecure

Automatisation du Plan de Continuité et de Reprise d'Activité pour l'infrastructure FinSecure.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           DC-PARIS (Principal)                          │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │   HAProxy   │    │   Nginx     │    │   Nginx     │                 │
│  │   (LB)      │───▶│   App-01    │    │   App-02    │                 │
│  └─────────────┘    └──────┬──────┘    └──────┬──────┘                 │
│                            │                   │                        │
│                     ┌──────▼───────────────────▼──────┐                 │
│                     │      PostgreSQL Primary         │                 │
│                     │      + Redis Cluster            │                 │
│                     └──────────────┬──────────────────┘                 │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │ Réplication streaming
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           DC-LYON (Secours)                             │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │   HAProxy   │    │   Nginx     │    │   Nginx     │                 │
│  │   (Standby) │    │   App-01    │    │   App-02    │                 │
│  └─────────────┘    └─────────────┘    └─────────────┘                 │
│                                                                         │
│                     ┌───────────────────────────────┐                   │
│                     │   PostgreSQL Standby          │                   │
│                     │   + Redis Replica             │                   │
│                     └───────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Exigences RTO/RPO

| Service | RTO | RPO |
|---------|-----|-----|
| API de paiement | 15 minutes | 0 (synchrone) |
| Base de données transactions | 15 minutes | 5 minutes |
| Portail client | 1 heure | 1 heure |
| Back-office | 4 heures | 24 heures |

## Prérequis

- Vagrant 2.3+ et VirtualBox 7+
- Ansible 2.14+
- Python 3.10+

## Installation

```bash
# Cloner le projet
cd pca-pra-ansible

# Installer les collections Ansible
ansible-galaxy collection install -r collections/requirements.yml

# Démarrer les VMs
vagrant up

# Ou déployer manuellement
ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml
```

## Structure du Projet

```
pca-pra-ansible/
├── ansible.cfg                 # Configuration Ansible
├── Vagrantfile                 # Configuration des VMs
├── inventories/
│   ├── production/             # Inventaire production
│   │   ├── hosts.yml
│   │   └── group_vars/
│   └── dr_test/                # Inventaire pour tests DR
├── playbooks/
│   ├── site.yml                # Playbook principal
│   ├── failover/               # Playbooks de failover
│   ├── failback/               # Playbooks de failback
│   ├── backup/                 # Playbooks de sauvegarde
│   └── dr_test/                # Tests de reprise
├── roles/
│   ├── common/                 # Configuration de base
│   ├── database/               # PostgreSQL
│   ├── application/            # Serveurs d'application
│   ├── loadbalancer/           # HAProxy
│   ├── backup/                 # pgBackRest
│   └── monitoring/             # Prometheus/Grafana
├── docker/                     # Fichiers Docker Compose
└── docs/runbooks/              # Documentation opérationnelle
```

## Utilisation

### Déploiement initial

```bash
# Déploiement complet
ansible-playbook playbooks/site.yml

# Déploiement par composant
ansible-playbook playbooks/site.yml --tags database
ansible-playbook playbooks/site.yml --tags application
```

### Sauvegardes

```bash
# Sauvegarde complète
ansible-playbook playbooks/backup/backup_database.yml -e backup_type=full

# Sauvegarde différentielle
ansible-playbook playbooks/backup/backup_database.yml -e backup_type=diff
```

### Failover

```bash
# Failover base de données uniquement
ansible-playbook playbooks/failover/database_failover.yml

# Failover complet
ansible-playbook playbooks/failover/full_failover.yml -e confirm_failover=true
```

### Failback

```bash
# Failback complet vers DC-Paris
ansible-playbook playbooks/failback/full_failback.yml
```

### Tests DR

```bash
# Test DR complet (trimestriel)
ansible-playbook playbooks/dr_test/full_dr_test.yml -i inventories/dr_test/hosts.yml

# Test partiel (mensuel)
ansible-playbook playbooks/dr_test/partial_dr_test.yml
```

## Réponses aux Questions du TP

### Exercice 1 - Configuration de l'inventaire

**1. Pourquoi séparer les groupes par datacenter ET par fonction ?**

La séparation par datacenter (`dc_paris`, `dc_lyon`) permet d'appliquer des configurations spécifiques à chaque site (adresses réseau, rôles primary/standby), tandis que la séparation par fonction (`databases`, `app_servers`, `loadbalancers`) permet d'exécuter des playbooks ciblés sur un type de composant sans se soucier de leur localisation. Cette double organisation offre une flexibilité maximale pour les opérations de maintenance et les procédures de failover.

**2. Comment les variables de groupe permettent-elles de différencier les configurations ?**

Les variables de groupe (`group_vars/dc_paris.yml`, `group_vars/dc_lyon.yml`) définissent les paramètres spécifiques à chaque datacenter : rôle (primary/standby), configuration réseau, paramètres de réplication. Ces variables sont automatiquement appliquées aux hosts du groupe correspondant, permettant d'utiliser les mêmes rôles Ansible avec des configurations différentes selon le contexte.

**3. Quel est l'intérêt d'avoir des groupes fonctionnels cross-DC ?**

Les groupes cross-DC (`databases`, `critical_services`) permettent d'orchestrer des opérations qui concernent un type de service indépendamment de sa localisation. Par exemple, le groupe `databases` permet de vérifier l'état de réplication entre primary et standby, tandis que `critical_services` permet d'appliquer des politiques de monitoring uniformes aux composants ayant le même RTO.

## Accès aux Services

### DC-Paris (Production)
- HAProxy: http://192.168.56.10 (ou localhost:8080)
- HAProxy Stats: http://192.168.56.10:8404/stats
- PostgreSQL: 192.168.56.10:5432
- Redis: 192.168.56.10:6379

### DC-Lyon (Secours)
- HAProxy: http://192.168.56.20 (ou localhost:9080)
- HAProxy Stats: http://192.168.56.20:8404/stats
- PostgreSQL: 192.168.56.20:5432
- Redis: 192.168.56.20:6379

## Documentation

- [Runbook Failover](docs/runbooks/failover_runbook.md)
- [Architecture détaillée](docs/architecture.md)

## Auteur

Projet réalisé dans le cadre du TP Ansible PCA/PRA.
