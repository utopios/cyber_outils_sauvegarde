# Travaux Pratiques Ansible
## Automatisation PCA/PRA - Plan de Continuité et de Reprise d'Activité



### Présentation du cas d'étude

Vous êtes intégré à l'équipe **Infrastructure et Sécurité** de la société **FinSecure**, une fintech spécialisée dans les services de paiement. Suite à une analyse d'impact (BIA), la direction a défini les exigences suivantes :

| Service | RTO | RPO |
|---------|-----|-----|
| API de paiement | 15 minutes | 0 (synchrone) |
| Base de données transactions | 15 minutes | 5 minutes |
| Portail client | 1 heure | 1 heure |
| Back-office | 4 heures | 24 heures |

### Architecture cible

L'infrastructure repose sur **deux sites géographiquement distincts** :

- **Site principal (DC-PARIS)** : Production active
- **Site de secours (DC-LYON)** : Standby avec réplication

**Composants techniques :**

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

### Environnement de travail

Pour ce TP, vous utiliserez un environnement virtualisé avec **Vagrant** ou **Docker Compose** simulant les deux datacenters.

---

## Préparation de l'environnement


### Structure du projet Ansible

Créez l'arborescence suivante pour organiser votre projet PCA/PRA :

```bash
pca-pra-ansible/
├── ansible.cfg
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       ├── dc_paris.yml
│   │       └── dc_lyon.yml
│   └── dr_test/
│       └── hosts.yml
├── playbooks/
│   ├── failover/
│   │   ├── database_failover.yml
│   │   ├── application_failover.yml
│   │   └── full_failover.yml
│   ├── failback/
│   │   ├── database_failback.yml
│   │   └── full_failback.yml
│   ├── backup/
│   │   ├── backup_database.yml
│   │   ├── backup_configs.yml
│   │   └── backup_full.yml
│   └── dr_test/
│       ├── full_dr_test.yml
│       └── partial_dr_test.yml
├── roles/
│   ├── common/
│   ├── database/
│   ├── application/
│   ├── loadbalancer/
│   └── monitoring/
├── collections/
│   └── requirements.yml
├── templates/
│   └── reports/
├── docs/
│   └── runbooks/
└── tests/
    └── molecule/
```

### Exercice 1 - Configuration de l'inventaire

> **Objectif** : Créer un inventaire dynamique représentant les deux datacenters


**Questions à traiter :**

1. Pourquoi séparer les groupes par datacenter ET par fonction ?
2. Comment les variables de groupe permettent-elles de différencier les configurations ?
3. Quel est l'intérêt d'avoir des groupes fonctionnels cross-DC ?


---

## Automatisation des sauvegardes


### Exercice 2 - Rôle de sauvegarde PostgreSQL

> **Objectif** : Créer un rôle Ansible pour automatiser les sauvegardes conformes au RPO


**Travail demandé :**

1. [ ] Créez le playbook `playbooks/backup/backup_database.yml` qui appelle ce rôle
2. [ ] Ajoutez un handler pour notifier en cas d'échec (Slack/email)
3. [ ] Implémentez la sauvegarde incrémentale avec `pgBackRest`
4. [ ] Créez une tâche de vérification de restaurabilité (test restore sur standby)

---

## Procédures de Failover


### Exercice 3 - Playbook de failover base de données

> **ATTENTION** : Ce playbook sera exécuté en situation de crise. La clarté, l'idempotence et la traçabilité sont cruciales.

**Travail demandé :**

1. [ ] Créez le playbook de failover applicatif `application_failover.yml`
2. [ ] Implémentez le playbook `full_failover.yml` qui orchestre DB + App + LB
3. [ ] Ajoutez un mécanisme de rollback automatique si la phase 4 échoue
4. [ ] Créez les templates de notification (Slack, email)

---

##  Tests de Reprise Automatisés


### Exercice 4 - Framework de test DR

> **Objectif** : Automatiser les tests trimestriels de reprise d'activité

**Travail demandé :**

1. [ ] Créez le template `dr_test_report.md.j2` avec toutes les métriques
2. [ ] Implémentez `partial_dr_test.yml` pour tester uniquement la DB
3. [ ] Ajoutez des tests de charge post-failover avec `locust` ou `wrk`
4. [ ] Créez un pipeline CI/CD qui exécute le test DR mensuellement
