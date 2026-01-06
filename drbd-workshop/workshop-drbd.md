# Workshop DRBD - Haute Disponibilite avec Replication de Donnees

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                    ARCHITECTURE DRBD                            │
    │                                                                 │
    │   ┌─────────────────┐              ┌─────────────────┐          │
    │   │     NODE 1      │              │     NODE 2      │          │
    │   │   (Primary)     │              │  (Secondary)    │          │
    │   │                 │              │                 │          │
    │   │  ┌───────────┐  │   TCP/IP     │  ┌───────────┐  │          │
    │   │  │Application│  │◄────────────►│  │  Standby  │  │          │
    │   │  └─────┬─────┘  │  Port 7788   │  └───────────┘  │          │
    │   │        │        │              │                 │          │
    │   │        ▼        │              │                 │          │
    │   │  ┌───────────┐  │  Replication │  ┌───────────┐  │          │
    │   │  │   /dev/   │  │◄────────────►│  │   /dev/   │  │          │
    │   │  │   drbd0   │  │   Synchrone  │  │   drbd0   │  │          │
    │   │  └─────┬─────┘  │  (Protocol C)│  └─────┬─────┘  │          │
    │   │        │        │              │        │        │          │
    │   │        ▼        │              │        ▼        │          │
    │   │  ┌───────────┐  │              │  ┌───────────┐  │          │
    │   │  │  Disque   │  │              │  │  Disque   │  │          │
    │   │  │  Physique │  │              │  │  Physique │  │          │
    │   │  └───────────┘  │              │  └───────────┘  │          │
    │   └─────────────────┘              └─────────────────┘          │
    └─────────────────────────────────────────────────────────────────┘
```

---

## Table des Matieres

1. [Introduction a DRBD](#1-introduction-a-drbd)
2. [Concepts Fondamentaux](#2-concepts-fondamentaux)
3. [Environnement de Lab Docker](#3-environnement-de-lab-docker)
4. [TP1 - Installation et Configuration de Base](#4-tp1---installation-et-configuration-de-base)
5. [TP2 - Modes de Replication](#5-tp2---modes-de-replication)
6. [TP3 - Failover et Haute Disponibilite](#6-tp3---failover-et-haute-disponibilite)
7. [TP4 - Integration avec une Base de Donnees](#7-tp4---integration-avec-une-base-de-donnees)
8. [TP5 - Monitoring et Troubleshooting](#8-tp5---monitoring-et-troubleshooting)
9. [Exercices Avances](#9-exercices-avances)
10. [Annexes](#10-annexes)

---

## 1. Introduction a DRBD

### Qu'est-ce que DRBD?

**DRBD (Distributed Replicated Block Device)** est une solution de replication de donnees au niveau bloc pour Linux. Il est souvent decrit comme un **"RAID 1 sur le reseau"**.

```
    ┌────────────────────────────────────────────────────────────┐
    │                    COMPARAISON RAID 1 vs DRBD              │
    │                                                            │
    │   RAID 1 Local                    DRBD Distribue           │
    │   ────────────                    ──────────────           │
    │                                                            │
    │   ┌─────────┐                     ┌─────────┐              │
    │   │ Serveur │                     │Serveur 1│──┐           │
    │   └────┬────┘                     └────┬────┘  │           │
    │        │                               │       │ Reseau    │
    │   ┌────┴────┐                     ┌────┴────┐  │           │
    │   │ RAID    │                     │  DRBD   │  │           │
    │   │Controller                     │ Kernel  │  │           │
    │   └────┬────┘                     └────┬────┘  │           │
    │    ┌───┴───┐                      ┌────┴────┐  │           │
    │   ┌┴┐     ┌┴┐                     │ Disque  │  │           │
    │   │D│     │D│                     └─────────┘  │           │
    │   │1│     │2│                                  │           │
    │   └─┘     └─┘                     ┌─────────┐  │           │
    │   Meme Serveur                    │Serveur 2│◄─┘           │
    │                                   └────┬────┘              │
    │                                   ┌────┴────┐              │
    │                                   │  DRBD   │              │
    │                                   │ Kernel  │              │
    │                                   └────┬────┘              │
    │                                   ┌────┴────┐              │
    │                                   │ Disque  │              │
    │                                   └─────────┘              │
    └────────────────────────────────────────────────────────────┘
```

### Avantages de DRBD

| Avantage | Description |
|----------|-------------|
| **Haute Disponibilite** | Basculement automatique en cas de panne |
| **Replication Temps Reel** | Donnees synchronisees en permanence |
| **Transparence** | Les applications n'ont pas conscience de DRBD |
| **Flexibilite** | Plusieurs modes de replication disponibles |
| **Open Source** | Integre au kernel Linux depuis la version 2.6.33 |

### Cas d'Usage Typiques

1. **Cluster de Bases de Donnees**
   - MySQL/MariaDB en haute disponibilite
   - PostgreSQL avec failover automatique

2. **Stockage Partage pour Cluster HA**
   - Remplacement de SAN couteux
   - Stockage pour machines virtuelles

3. **Replication Entre Sites**
   - Disaster Recovery
   - Replication geographique

---

## 2. Concepts Fondamentaux

### 2.1 Modes de Replication (Protocols)

DRBD propose trois protocoles de replication:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      PROTOCOLES DE REPLICATION DRBD                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PROTOCOL A - Asynchrone                                                │
│  ────────────────────────                                               │
│  ┌──────┐    Write     ┌──────┐                                         │
│  │ App  │─────────────►│ DRBD │──► ACK immediat                         │
│  └──────┘              └──────┘                                         │
│                            │                                            │
│                            └──► Envoi reseau en arriere-plan            │
│                                                                         │
│  + Performance maximale                                                 │
│  - Risque de perte de donnees en cas de crash                           │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PROTOCOL B - Semi-synchrone                                            │
│  ───────────────────────────                                            │
│  ┌──────┐    Write     ┌──────┐   TCP Send    ┌──────┐                  │
│  │ App  │─────────────►│ DRBD │─────────────►│Remote│                   │
│  └──────┘              └──────┘◄─────────────└──────┘                   │
│                            │      TCP ACK                               │
│                            └──► ACK apres envoi reseau                  │
│                                                                         │
│  + Bon compromis performance/securite                                   │
│  - Donnees peuvent etre en transit lors d'un crash                      │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PROTOCOL C - Synchrone (Recommande pour HA)                            │
│  ───────────────────────────────────────────                            │
│  ┌──────┐    Write     ┌──────┐   Replicate   ┌──────┐                  │
│  │ App  │─────────────►│ DRBD │─────────────►│Remote│                   │
│  └──────┘              └──────┘◄─────────────└──────┘                   │
│                            │      Write ACK                             │
│                            └──► ACK apres ecriture distante             │
│                                                                         │
│  + Securite maximale - zero perte de donnees                            │
│  - Latence plus elevee                                                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Roles des Noeuds

```
┌────────────────────────────────────────────────────────────┐
│                    ROLES DES NOEUDS DRBD                   │
├────────────────────────────────────────────────────────────┤
│                                                            │
│   PRIMARY                         SECONDARY                │
│   ───────                         ─────────                │
│   ┌─────────────┐                 ┌─────────────┐          │
│   │    R/W      │                 │    R/O      │          │
│   │  Lecture    │                 │  Lecture    │          │
│   │  Ecriture   │                 │  Seulement  │          │
│   └──────┬──────┘                 └──────┬──────┘          │
│          │                               │                 │
│          ▼                               ▼                 │
│   ┌─────────────┐                 ┌─────────────┐          │
│   │  Montable   │                 │ Non Montable│          │
│   │  (ext4/xfs) │                 │  (standby)  │          │
│   └─────────────┘                 └─────────────┘          │
│                                                            │
│   Note: En mode "dual-primary", les deux noeuds            │
│         peuvent etre Primary simultanement                 │
│         (necessite un filesystem cluster: GFS2, OCFS2)     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 2.3 Etats de Synchronisation

| Etat | Description |
|------|-------------|
| **UpToDate/UpToDate** | Les deux noeuds sont synchronises |
| **UpToDate/Inconsistent** | Synchronisation initiale en cours |
| **UpToDate/Outdated** | Le secondaire a pris du retard |
| **StandAlone** | Noeud deconnecte du cluster |

### 2.4 Split-Brain

Le **split-brain** se produit quand les deux noeuds perdent la connexion et continuent d'operer independamment:

```
┌─────────────────────────────────────────────────────────────────┐
│                    SCENARIO SPLIT-BRAIN                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   AVANT (Normal)                                                │
│   ┌─────────┐          ┌─────────┐                              │
│   │ Node 1  │◄────────►│ Node 2  │                              │
│   │ Primary │  Sync    │Secondary│                              │
│   └─────────┘          └─────────┘                              │
│                                                                 │
│   PENDANT (Split-Brain)                                         │
│   ┌─────────┐    X     ┌─────────┐                              │
│   │ Node 1  │    X     │ Node 2  │                              │
│   │ Primary │    X     │ Primary │  <- Les deux pensent         │
│   │ Write A │          │ Write B │     etre Primary!            │
│   └─────────┘          └─────────┘                              │
│                                                                 │
│   RESOLUTION                                                    │
│   - Manuelle: choisir quel noeud garde ses donnees              │
│   - Automatique: politique de resolution configuree             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Environnement de Lab Docker

### 3.1 Architecture du Lab

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ARCHITECTURE DU LAB DOCKER                          │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Docker Network: drbd_net                     │   │
│   │                       172.28.0.0/16                              │   │
│   │                                                                 │   │
│   │   ┌─────────────────┐              ┌─────────────────┐          │   │
│   │   │    drbd-node1   │              │    drbd-node2   │          │   │
│   │   │   172.28.0.11   │              │   172.28.0.12   │          │   │
│   │   │                 │              │                 │          │   │
│   │   │  ┌───────────┐  │    TCP       │  ┌───────────┐  │          │   │
│   │   │  │  DRBD     │  │◄──7788──────►│  │  DRBD     │  │          │   │
│   │   │  │  /dev/    │  │              │  │  /dev/    │  │          │   │
│   │   │  │  drbd0    │  │              │  │  drbd0    │  │          │   │
│   │   │  └─────┬─────┘  │              │  └─────┬─────┘  │          │   │
│   │   │        │        │              │        │        │          │   │
│   │   │  ┌─────┴─────┐  │              │  ┌─────┴─────┐  │          │   │
│   │   │  │  Volume   │  │              │  │  Volume   │  │          │   │
│   │   │  │  Docker   │  │              │  │  Docker   │  │          │   │
│   │   │  └───────────┘  │              │  └───────────┘  │          │   │
│   │   └─────────────────┘              └─────────────────┘          │   │
│   │                                                                 │   │
│   │   ┌─────────────────┐                                           │   │
│   │   │    db-server    │  <- Serveur PostgreSQL                    │   │
│   │   │   172.28.0.20   │     pour TP avance                        │   │
│   │   └─────────────────┘                                           │   │
│   │                                                                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Limitations Docker pour DRBD

> **Important**: DRBD est un module kernel et ne peut pas fonctionner nativement dans des conteneurs Docker standards. Pour ce workshop, nous utilisons une approche **simulee** qui reproduit les concepts et comportements de DRBD sans necessiter l'acces au kernel.

Pour une utilisation en production, vous devrez:
- Utiliser des VMs (VirtualBox, KVM, etc.)
- Ou des conteneurs privilegies avec acces au module DRBD du host

### 3.3 Structure des Fichiers

```
drbd-workshop/
├── docker-compose.yaml
├── workshop-drbd.md
├── node1/
│   ├── Dockerfile
│   └── drbd.conf
├── node2/
│   ├── Dockerfile
│   └── drbd.conf
├── scripts/
│   ├── setup-drbd.sh
│   ├── failover.sh
│   ├── monitor.sh
│   ├── simulate-failure.sh
│   └── benchmark.sh
└── solutions/
    ├── tp1-solution.sh
    ├── tp2-solution.sh
    ├── tp3-solution.sh
    └── tp4-solution.sh
```

---

## 4. TP1 - Installation et Configuration de Base

### Objectifs
- Comprendre l'architecture DRBD
- Configurer un cluster DRBD a deux noeuds
- Effectuer la synchronisation initiale

### Etape 1: Demarrer l'environnement

```bash
# Cloner ou se placer dans le repertoire du workshop
cd drbd-workshop

# Demarrer les conteneurs
docker-compose up -d

# Verifier que les conteneurs sont en cours d'execution
docker-compose ps
```

### Etape 2: Explorer la configuration DRBD

Connectez-vous au premier noeud:

```bash
docker exec -it drbd-node1 bash
```

Examinez la configuration DRBD:

```bash
# Voir la configuration
cat /etc/drbd.d/r0.res

# Structure attendue:
# resource r0 {
#     protocol C;
#     on node1 {
#         device /dev/drbd0;
#         disk /dev/sda1;
#         address 172.28.0.11:7788;
#         meta-disk internal;
#     }
#     on node2 {
#         device /dev/drbd0;
#         disk /dev/sda1;
#         address 172.28.0.12:7788;
#         meta-disk internal;
#     }
# }
```

### Etape 3: Initialiser DRBD (Simulation)

Sur le **Node 1**:

```bash
# Creer les metadonnees DRBD
/scripts/drbd-init.sh create-md

# Demarrer DRBD
/scripts/drbd-init.sh start

# Definir comme Primary et forcer la sync initiale
/scripts/drbd-init.sh primary --force
```

Sur le **Node 2**:

```bash
docker exec -it drbd-node2 bash

# Creer les metadonnees
/scripts/drbd-init.sh create-md

# Demarrer DRBD (deviendra automatiquement Secondary)
/scripts/drbd-init.sh start
```

### Etape 4: Verifier l'etat du cluster

```bash
# Sur n'importe quel noeud
/scripts/drbd-status.sh

# Sortie attendue:
# ┌─────────────────────────────────────────────────┐
# │ DRBD Status - Resource: r0                      │
# ├─────────────────────────────────────────────────┤
# │ Node 1 (172.28.0.11)                            │
# │   Role: Primary                                 │
# │   Disk State: UpToDate                          │
# │   Connection: Connected                         │
# │                                                 │
# │ Node 2 (172.28.0.12)                            │
# │   Role: Secondary                               │
# │   Disk State: UpToDate                          │
# │   Connection: Connected                         │
# │                                                 │
# │ Sync Status: 100% synchronized                  │
# └─────────────────────────────────────────────────┘
```

### Etape 5: Tester la replication

Sur le **Node 1 (Primary)**:

```bash
# Monter le device DRBD
mkdir -p /mnt/drbd
mount /dev/drbd0 /mnt/drbd

# Creer des fichiers de test
echo "Donnees critiques - $(date)" > /mnt/drbd/test.txt
dd if=/dev/urandom of=/mnt/drbd/data.bin bs=1M count=10

# Verifier
ls -la /mnt/drbd/
```

### Exercice 1.1: Questions de Comprehension

1. Pourquoi le Node 2 ne peut-il pas monter `/dev/drbd0` directement?
2. Que se passe-t-il si on essaie d'ecrire sur le Secondary?
3. Quelle est la difference entre `meta-disk internal` et `meta-disk /dev/sdb1`?

### Exercice 1.2: Configuration Personnalisee

Modifiez la configuration pour:
- Changer le port de replication de 7788 a 7799
- Ajouter un rate limit de 100M pour la synchronisation

---

## 5. TP2 - Modes de Replication

### Objectifs
- Comparer les trois protocoles de replication
- Mesurer l'impact sur les performances
- Choisir le protocole adapte au cas d'usage

### Etape 1: Tester Protocol A (Asynchrone)

```bash
# Sur Node 1
docker exec -it drbd-node1 bash

# Modifier le protocole
/scripts/change-protocol.sh A

# Lancer un benchmark d'ecriture
/scripts/benchmark.sh write

# Observer les metriques
/scripts/monitor.sh latency
```

### Etape 2: Tester Protocol B (Semi-synchrone)

```bash
# Changer pour Protocol B
/scripts/change-protocol.sh B

# Relancer le benchmark
/scripts/benchmark.sh write

# Comparer les resultats
```

### Etape 3: Tester Protocol C (Synchrone)

```bash
# Changer pour Protocol C
/scripts/change-protocol.sh C

# Relancer le benchmark
/scripts/benchmark.sh write
```

### Etape 4: Analyser les Resultats

```
┌────────────────────────────────────────────────────────────────────┐
│              RESULTATS BENCHMARK (Exemple)                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Protocol   │ Throughput  │ Latency (avg) │ Data Safety           │
│  ───────────┼─────────────┼───────────────┼─────────────────────   │
│  A (Async)  │ 450 MB/s    │ 0.5 ms        │ Possible data loss    │
│  B (Semi)   │ 320 MB/s    │ 2.1 ms        │ In-flight data risk   │
│  C (Sync)   │ 180 MB/s    │ 4.8 ms        │ Zero data loss        │
│                                                                    │
│  Note: Les resultats varient selon la latence reseau              │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Exercice 2.1: Choix du Protocole

Pour chaque scenario, indiquez le protocole recommande et justifiez:

| Scenario | Protocole | Justification |
|----------|-----------|---------------|
| Base de donnees financieres | ? | ? |
| Serveur de logs | ? | ? |
| Cluster de virtualisation | ? | ? |
| Replication inter-datacenter (100ms latency) | ? | ? |

### Exercice 2.2: Simulation de Latence Reseau

```bash
# Ajouter 50ms de latence
/scripts/simulate-latency.sh 50ms

# Relancer les benchmarks et observer l'impact
# sur chaque protocole
```

---

## 6. TP3 - Failover et Haute Disponibilite

### Objectifs
- Configurer le basculement manuel
- Simuler une panne et recuperer
- Comprendre le split-brain

### Etape 1: Basculement Manuel (Planned Failover)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PROCESSUS DE FAILOVER MANUEL                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1. Demonter le FS sur Primary                                     │
│      ┌─────────┐                                                    │
│      │ Node 1  │ umount /mnt/drbd                                   │
│      │ Primary │                                                    │
│      └─────────┘                                                    │
│                                                                     │
│   2. Passer Primary en Secondary                                    │
│      ┌─────────┐                                                    │
│      │ Node 1  │ drbdadm secondary r0                               │
│      │Secondary│                                                    │
│      └─────────┘                                                    │
│                                                                     │
│   3. Promouvoir l'ancien Secondary                                  │
│      ┌─────────┐                                                    │
│      │ Node 2  │ drbdadm primary r0                                 │
│      │ Primary │                                                    │
│      └─────────┘                                                    │
│                                                                     │
│   4. Monter le FS sur le nouveau Primary                            │
│      ┌─────────┐                                                    │
│      │ Node 2  │ mount /dev/drbd0 /mnt/drbd                         │
│      │ Primary │                                                    │
│      └─────────┘                                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

Sur **Node 1** (Primary actuel):

```bash
# Arreter les applications utilisant le volume
# (dans notre cas, aucune)

# Demonter le filesystem
umount /mnt/drbd

# Passer en Secondary
/scripts/drbd-role.sh secondary
```

Sur **Node 2** (nouveau Primary):

```bash
docker exec -it drbd-node2 bash

# Promouvoir en Primary
/scripts/drbd-role.sh primary

# Monter le filesystem
mkdir -p /mnt/drbd
mount /dev/drbd0 /mnt/drbd

# Verifier que les donnees sont presentes
ls -la /mnt/drbd/
cat /mnt/drbd/test.txt
```

### Etape 2: Simulation de Panne (Unplanned Failover)

```bash
# Sur le host Docker, simuler un crash du Node 1
docker stop drbd-node1 --time=0

# Sur Node 2, observer l'etat
docker exec -it drbd-node2 bash
/scripts/drbd-status.sh

# Le Node 2 detecte la perte de connexion
# Etat: StandAlone ou WFConnection
```

Forcer la promotion sur Node 2:

```bash
# Promouvoir malgre l'absence du peer
/scripts/drbd-role.sh primary --force

# Monter et continuer les operations
mount /dev/drbd0 /mnt/drbd
```

### Etape 3: Recuperation apres Panne

```bash
# Redemarrer Node 1
docker start drbd-node1

# Sur Node 1, verifier l'etat
docker exec -it drbd-node1 bash
/scripts/drbd-status.sh

# Node 1 devrait se resynchroniser automatiquement
# comme Secondary
```

### Etape 4: Gestion du Split-Brain

```bash
# Simuler un split-brain
/scripts/simulate-splitbrain.sh

# Observer l'etat
/scripts/drbd-status.sh
# Etat attendu: StandAlone sur les deux noeuds
```

Resolution du split-brain:

```bash
# Sur le noeud qui doit PERDRE ses donnees (Node 2 par exemple)
docker exec -it drbd-node2 bash
/scripts/resolve-splitbrain.sh discard-local

# Sur le noeud qui garde ses donnees (Node 1)
docker exec -it drbd-node1 bash
/scripts/resolve-splitbrain.sh keep-local
```

### Exercice 3.1: Automatisation du Failover

Creez un script qui:
1. Detecte la panne du Primary
2. Attend 30 secondes (grace period)
3. Promeut automatiquement le Secondary
4. Envoie une notification

### Exercice 3.2: Configuration Anti-Split-Brain

Configurez les handlers de split-brain:
```
handlers {
    split-brain "/scripts/notify-splitbrain.sh";
}
net {
    after-sb-0pri discard-younger-primary;
    after-sb-1pri discard-secondary;
    after-sb-2pri disconnect;
}
```

---

## 7. TP4 - Integration avec une Base de Donnees

### Objectifs
- Deployer PostgreSQL sur DRBD
- Effectuer un failover de base de donnees
- Garantir la coherence des donnees

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│               POSTGRESQL SUR DRBD - HAUTE DISPONIBILITE                 │
│                                                                         │
│   ┌─────────────────────────────┐    ┌─────────────────────────────┐    │
│   │         NODE 1              │    │         NODE 2              │    │
│   │                             │    │                             │    │
│   │  ┌───────────────────────┐  │    │  ┌───────────────────────┐  │    │
│   │  │     PostgreSQL        │  │    │  │     PostgreSQL        │  │    │
│   │  │      (Active)         │  │    │  │     (Standby)         │  │    │
│   │  │    Port 5432          │  │    │  │    (non demarre)      │  │    │
│   │  └───────────┬───────────┘  │    │  └───────────────────────┘  │    │
│   │              │              │    │                             │    │
│   │              ▼              │    │                             │    │
│   │  ┌───────────────────────┐  │    │  ┌───────────────────────┐  │    │
│   │  │    /mnt/drbd/pgdata   │  │    │  │    /mnt/drbd/pgdata   │  │    │
│   │  │    (Mounted - R/W)    │  │    │  │    (Not Mounted)      │  │    │
│   │  └───────────┬───────────┘  │    │  └───────────┬───────────┘  │    │
│   │              │              │    │              │              │    │
│   │  ┌───────────┴───────────┐  │    │  ┌───────────┴───────────┐  │    │
│   │  │      /dev/drbd0       │  │    │  │      /dev/drbd0       │  │    │
│   │  │      (Primary)        │◄─┼────┼─►│      (Secondary)      │  │    │
│   │  └───────────────────────┘  │    │  └───────────────────────┘  │    │
│   │                             │    │                             │    │
│   └─────────────────────────────┘    └─────────────────────────────┘    │
│                                                                         │
│   En cas de failover:                                                   │
│   1. PostgreSQL s'arrete sur Node 1                                     │
│   2. DRBD bascule: Node 2 devient Primary                               │
│   3. Le FS est monte sur Node 2                                         │
│   4. PostgreSQL demarre sur Node 2                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Etape 1: Preparer le Stockage DRBD pour PostgreSQL

Sur **Node 1** (Primary):

```bash
docker exec -it drbd-node1 bash

# S'assurer que DRBD est Primary et monte
/scripts/drbd-status.sh

# Creer le repertoire pour PostgreSQL
mkdir -p /mnt/drbd/pgdata
chown -R postgres:postgres /mnt/drbd/pgdata
chmod 700 /mnt/drbd/pgdata
```

### Etape 2: Initialiser PostgreSQL

```bash
# Initialiser le cluster PostgreSQL
su - postgres -c "initdb -D /mnt/drbd/pgdata"

# Configurer PostgreSQL pour accepter les connexions
cat >> /mnt/drbd/pgdata/postgresql.conf << EOF
listen_addresses = '*'
port = 5432
max_connections = 100
EOF

cat >> /mnt/drbd/pgdata/pg_hba.conf << EOF
host    all    all    172.28.0.0/16    md5
EOF

# Demarrer PostgreSQL
su - postgres -c "pg_ctl -D /mnt/drbd/pgdata start"

# Creer une base de test
su - postgres -c "psql -c \"CREATE DATABASE testdb;\""
su - postgres -c "psql -d testdb -c \"CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());\""
```

### Etape 3: Inserer des Donnees de Test

```bash
# Inserer des donnees
su - postgres -c "psql -d testdb -c \"INSERT INTO test (data) SELECT 'Record ' || generate_series(1,1000);\""

# Verifier
su - postgres -c "psql -d testdb -c \"SELECT COUNT(*) FROM test;\""
```

### Etape 4: Effectuer un Failover de la Base

```bash
# Sur Node 1: Arreter proprement PostgreSQL
su - postgres -c "pg_ctl -D /mnt/drbd/pgdata stop"

# Demonter DRBD
umount /mnt/drbd

# Passer en Secondary
/scripts/drbd-role.sh secondary
```

Sur **Node 2**:

```bash
docker exec -it drbd-node2 bash

# Promouvoir en Primary
/scripts/drbd-role.sh primary

# Monter DRBD
mount /dev/drbd0 /mnt/drbd

# Demarrer PostgreSQL
su - postgres -c "pg_ctl -D /mnt/drbd/pgdata start"

# Verifier que les donnees sont intactes
su - postgres -c "psql -d testdb -c \"SELECT COUNT(*) FROM test;\""
```

### Etape 5: Script de Failover Automatise

```bash
# Utiliser le script de failover PostgreSQL
/scripts/pg-failover.sh

# Ce script effectue automatiquement:
# 1. Arret de PostgreSQL
# 2. Demontage DRBD
# 3. Changement de role
# 4. Notification
```

### Exercice 4.1: Test de Coherence

1. Lancez une transaction longue sur Node 1
2. Pendant la transaction, forcez un failover
3. Verifiez que la transaction a ete correctement annulee

### Exercice 4.2: Benchmark PostgreSQL

```bash
# Installer pgbench
apt-get install postgresql-contrib

# Initialiser pgbench
pgbench -i -s 10 testdb

# Lancer un benchmark
pgbench -c 10 -j 2 -T 60 testdb

# Comparer les performances avec et sans DRBD
```

---

## 8. TP5 - Monitoring et Troubleshooting

### Objectifs
- Mettre en place un monitoring DRBD
- Diagnostiquer les problemes courants
- Optimiser les performances

### 8.1 Monitoring en Temps Reel

```bash
# Script de monitoring continu
/scripts/monitor.sh watch

# Affichage:
┌─────────────────────────────────────────────────────────────────┐
│                    DRBD MONITOR - r0                            │
├─────────────────────────────────────────────────────────────────┤
│ Time: 2024-01-15 14:32:45                                       │
│                                                                 │
│ Connection State: Connected                                     │
│ Protocol: C (Synchronous)                                       │
│                                                                 │
│ Node 1 (172.28.0.11)          Node 2 (172.28.0.12)             │
│ ┌─────────────────────┐       ┌─────────────────────┐          │
│ │ Role: Primary       │       │ Role: Secondary     │          │
│ │ Disk: UpToDate      │◄─────►│ Disk: UpToDate      │          │
│ │ Mounted: Yes        │       │ Mounted: No         │          │
│ └─────────────────────┘       └─────────────────────┘          │
│                                                                 │
│ Sync Progress: 100%  ████████████████████████████  Complete    │
│                                                                 │
│ Network Stats:                                                  │
│   Sent: 1.2 GB    Received: 45 MB    Pending: 0                │
│   Unacked: 0      OutOfSync: 0 KB                              │
│                                                                 │
│ Performance (last 60s):                                         │
│   Write: 125 MB/s    Read: 340 MB/s    IOPS: 15,234            │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Metriques Importantes

```bash
# Voir les statistiques detaillees
/scripts/drbd-stats.sh

# Metriques a surveiller:
# - ns (network send): bytes envoyes
# - nr (network receive): bytes recus
# - dw (disk write): ecritures disque
# - dr (disk read): lectures disque
# - pe (pending): I/O en attente
# - ua (unacked): ecritures non acquittees
# - oos (out of sync): KB non synchronises
```

### 8.3 Alertes et Notifications

Configuration des alertes:

```bash
# /etc/drbd.d/handlers.res
handlers {
    pri-on-incon-degr "/scripts/alert.sh degraded";
    pri-lost-after-sb "/scripts/alert.sh splitbrain";
    local-io-error "/scripts/alert.sh io-error";
    fence-peer "/scripts/alert.sh fence-peer";
}
```

### 8.4 Troubleshooting Guide

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GUIDE DE TROUBLESHOOTING DRBD                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│ PROBLEME: "StandAlone" sur les deux noeuds                             │
│ ─────────────────────────────────────────────                           │
│ Cause: Perte de connexion reseau ou split-brain                        │
│ Solution:                                                               │
│   1. Verifier la connectivite reseau (ping)                            │
│   2. Verifier le firewall (port 7788)                                  │
│   3. Reconnecter: drbdadm connect r0                                   │
│                                                                         │
│ PROBLEME: "Inconsistent" disk state                                    │
│ ───────────────────────────────────────                                 │
│ Cause: Synchronisation initiale incomplete                             │
│ Solution:                                                               │
│   1. Attendre la fin de la sync                                        │
│   2. Si bloque: drbdadm invalidate r0 (sur secondary)                  │
│                                                                         │
│ PROBLEME: "WFConnection" (Waiting For Connection)                      │
│ ─────────────────────────────────────────────────                       │
│ Cause: Le peer n'est pas joignable                                     │
│ Solution:                                                               │
│   1. Verifier que DRBD est demarre sur le peer                         │
│   2. Verifier la configuration reseau                                  │
│   3. Verifier les adresses IP dans drbd.conf                           │
│                                                                         │
│ PROBLEME: Performances degradees                                        │
│ ─────────────────────────────────                                       │
│ Causes possibles:                                                       │
│   - Latence reseau elevee                                              │
│   - Disque lent                                                        │
│   - Buffer trop petit                                                  │
│ Solutions:                                                              │
│   1. Augmenter sndbuf-size et rcvbuf-size                             │
│   2. Utiliser Protocol A si la securite le permet                      │
│   3. Activer le write-back cache du disque                             │
│                                                                         │
│ PROBLEME: Split-brain detecte                                          │
│ ─────────────────────────────────                                       │
│ Solution:                                                               │
│   1. Identifier le noeud avec les bonnes donnees                       │
│   2. Sur l'autre: drbdadm disconnect r0                                │
│   3. drbdadm secondary r0                                              │
│   4. drbdadm -- --discard-my-data connect r0                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Exercice 5.1: Simulation de Pannes

```bash
# Simuler differentes pannes et les resoudre

# 1. Panne reseau temporaire
/scripts/simulate-failure.sh network 30s

# 2. Disque lent
/scripts/simulate-failure.sh slow-disk

# 3. Disque plein
/scripts/simulate-failure.sh disk-full

# 4. Crash du processus DRBD
/scripts/simulate-failure.sh crash
```

### Exercice 5.2: Optimisation

Optimisez la configuration pour:
1. Minimiser la latence d'ecriture
2. Maximiser le throughput de synchronisation
3. Reduire l'utilisation CPU

---

## 9. Exercices Avances

### Exercice 9.1: DRBD Multi-Ressources

Configurez deux ressources DRBD independantes:
- `r0` pour les donnees applicatives
- `r1` pour les logs

```
resource r0 { ... }
resource r1 {
    protocol A;  # Logs peuvent utiliser async
    ...
}
```

### Exercice 9.2: Cluster a 3 Noeuds

```
┌─────────────────────────────────────────────────────────────────┐
│                    CLUSTER DRBD 3 NOEUDS                        │
│                                                                 │
│        ┌─────────┐                                              │
│        │ Node 1  │                                              │
│        │ Primary │                                              │
│        └────┬────┘                                              │
│             │                                                   │
│      ┌──────┴──────┐                                            │
│      │             │                                            │
│      ▼             ▼                                            │
│ ┌─────────┐   ┌─────────┐                                       │
│ │ Node 2  │   │ Node 3  │                                       │
│ │Secondary│   │Secondary│                                       │
│ └─────────┘   └─────────┘                                       │
│                                                                 │
│ Configuration: "stacked" ou DRBD 9 natif                        │
└─────────────────────────────────────────────────────────────────┘
```

### Exercice 9.3: Integration Pacemaker/Corosync

Creez une configuration complete avec:
- Pacemaker pour la gestion du cluster
- DRBD comme ressource gere
- Failover automatique

### Exercice 9.4: Disaster Recovery Inter-Site

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    REPLICATION INTER-SITE                               │
│                                                                         │
│   Site Principal (Paris)              Site DR (Lyon)                    │
│   ┌─────────────────────┐             ┌─────────────────────┐           │
│   │ ┌─────┐   ┌─────┐   │   WAN       │ ┌─────┐   ┌─────┐   │           │
│   │ │ N1  │◄─►│ N2  │   │◄───────────►│ │ N3  │◄─►│ N4  │   │           │
│   │ └─────┘   └─────┘   │  Protocol A │ └─────┘   └─────┘   │           │
│   │    Protocol C       │             │    Protocol C       │           │
│   └─────────────────────┘             └─────────────────────┘           │
│                                                                         │
│   - Replication synchrone intra-site (Protocol C)                       │
│   - Replication asynchrone inter-site (Protocol A)                      │
│   - RPO intra-site: 0                                                   │
│   - RPO inter-site: quelques secondes                                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Annexes

### A. Commandes DRBD Essentielles

```bash
# Gestion des ressources
drbdadm up r0              # Demarrer une ressource
drbdadm down r0            # Arreter une ressource
drbdadm primary r0         # Passer en Primary
drbdadm secondary r0       # Passer en Secondary

# Synchronisation
drbdadm invalidate r0      # Forcer resync depuis peer
drbdadm invalidate-remote r0  # Forcer le peer a resync

# Connexion
drbdadm connect r0         # Connecter au peer
drbdadm disconnect r0      # Deconnecter du peer

# Status
drbdadm status r0          # Voir le status
drbdadm dstate r0          # Disk state
drbdadm cstate r0          # Connection state
drbdadm role r0            # Role actuel

# Configuration
drbdadm dump r0            # Afficher la config
drbdadm adjust r0          # Appliquer les changements
drbdadm create-md r0       # Creer les metadonnees
```

### B. Fichier de Configuration Complet

```
# /etc/drbd.d/global_common.conf
global {
    usage-count no;
}

common {
    handlers {
        pri-on-incon-degr "/usr/lib/drbd/notify-pri-on-incon-degr.sh";
        pri-lost-after-sb "/usr/lib/drbd/notify-pri-lost-after-sb.sh";
        local-io-error "/usr/lib/drbd/notify-io-error.sh";
    }

    startup {
        wfc-timeout 120;
        degr-wfc-timeout 60;
    }

    options {
        on-no-data-accessible io-error;
    }

    disk {
        on-io-error detach;
        no-disk-flushes;
        no-md-flushes;
    }

    net {
        protocol C;
        max-buffers 8000;
        max-epoch-size 8000;
        sndbuf-size 512k;
        rcvbuf-size 512k;
        after-sb-0pri discard-zero-changes;
        after-sb-1pri discard-secondary;
        after-sb-2pri disconnect;
    }
}

# /etc/drbd.d/r0.res
resource r0 {
    device /dev/drbd0;
    disk /dev/sda1;
    meta-disk internal;

    on node1 {
        address 172.28.0.11:7788;
    }
    on node2 {
        address 172.28.0.12:7788;
    }
}
```

### C. Performance Tuning

```bash
# Parametres kernel recommandes
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 16777216' >> /etc/sysctl.conf
sysctl -p

# Parametres DRBD pour haute performance
net {
    max-buffers 36k;
    sndbuf-size 1024k;
    rcvbuf-size 2048k;
}

disk {
    al-extents 3389;
    c-max-rate 720M;
}
```

### D. Checklist de Production

- [ ] Configuration reseau redondante
- [ ] Heartbeat/fencing configure
- [ ] Monitoring en place
- [ ] Alertes configurees
- [ ] Documentation a jour
- [ ] Procedures de failover testees
- [ ] Backups reguliers (meme avec DRBD!)
- [ ] Plan de DR documente
- [ ] Formation des equipes

### E. Ressources Supplementaires

- Documentation officielle: https://docs.linbit.com/
- Kernel documentation: https://www.kernel.org/doc/html/latest/admin-guide/blockdev/drbd/
- Community: https://github.com/LINBIT/drbd

---

## Quiz Final

1. Quelle est la principale difference entre DRBD et une replication applicative?
2. Dans quel cas utiliseriez-vous Protocol A plutot que Protocol C?
3. Comment DRBD gere-t-il un split-brain par defaut?
4. Pourquoi est-il important de toujours demonter le filesystem avant de changer de role?
5. Quelle est la difference entre `invalidate` et `invalidate-remote`?

---

**Felicitations!** Vous avez termine le workshop DRBD sur la haute disponibilite.
