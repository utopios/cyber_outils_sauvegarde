# Solution TP Sauvegarde - Ghostfolio avec BorgBackup

## Table des matieres

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture](#2-architecture)
3. [Etape 1: Mise en place de Ghostfolio](#etape-1-mise-en-place-de-lapplication-ghostfolio)
4. [Etape 2: Conception de l'architecture](#etape-2-conception-de-larchitecture-de-sauvegarde)
5. [Etape 3: Mise en place du borg-server](#etape-3-mise-en-place-du-serveur-borg-server)
6. [Etape 4: Mise en place du borg-client](#etape-4-mise-en-place-du-conteneur-borg-client)
7. [Etape 5: Sauvegarde complete](#etape-5-execution-dune-sauvegarde-complete)
8. [Etape 6: Simulation d'attaque](#etape-6-scenario-dattaque-simulation)
9. [Etape 7: Restauration](#etape-7-restauration-complete)
10. [Etape 8: Automatisation](#etape-8-mise-en-place-de-la-rotation-et-automatisation)

---

## 1. Vue d'ensemble

Cette solution met en place un systeme de sauvegarde securise pour l'application Ghostfolio en utilisant BorgBackup. Elle repond aux exigences de securite suivantes:

| Exigence | Implementation |
|----------|----------------|
| Externalisation | Serveur borg-server dedie sur reseau isole |
| Chiffrement cote client | BorgBackup avec encryption repokey-blake2 |
| Isolation | Deux reseaux Docker separes (app/backup) |
| Restauration post-incident | Scripts de restauration automatises |
| Automatisation | Cron job pour sauvegardes planifiees |
| Secrets non versions | Fichier .env + .gitignore |

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        RESEAU APP_NETWORK                        │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐            │
│  │  Ghostfolio │   │  PostgreSQL │   │    Redis    │            │
│  │   :3333     │──▶│    :5432    │   │    :6379    │            │
│  └─────────────┘   └──────┬──────┘   └─────────────┘            │
│                           │                                      │
│                    ┌──────┴──────┐                               │
│                    │ borg-client │                               │
│                    │  (pg_dump)  │                               │
│                    └──────┬──────┘                               │
└───────────────────────────┼─────────────────────────────────────┘
                            │ SSH (cle)
┌───────────────────────────┼─────────────────────────────────────┐
│                    ┌──────┴──────┐     RESEAU BACKUP_NETWORK     │
│                    │ borg-server │     (internal: true)          │
│                    │    :22      │                               │
│                    └──────┬──────┘                               │
│                           │                                      │
│                    ┌──────┴──────┐                               │
│                    │  Volume     │                               │
│                    │  borg_repo  │                               │
│                    └─────────────┘                               │
└─────────────────────────────────────────────────────────────────┘
```

### Composants

| Conteneur | Role | Reseau |
|-----------|------|--------|
| ghostfolio | Application web | app_network |
| postgres | Base de donnees | app_network |
| redis | Cache | app_network |
| borg-client | Effectue les sauvegardes | app_network + backup_network |
| borg-server | Stocke les sauvegardes | backup_network (isole) |

---

## Etape 1: Mise en place de l'application Ghostfolio

### 1.1 Generation des secrets

```bash
# Rendre les scripts executables
chmod +x generate-secrets.sh generate-ssh-keys.sh

# Generer le fichier .env avec des secrets securises
./generate-secrets.sh
```

Le script genere automatiquement:
- `POSTGRES_PASSWORD`: Mot de passe PostgreSQL
- `ACCESS_TOKEN_SALT`: Salt pour les tokens Ghostfolio
- `JWT_SECRET_KEY`: Cle secrete JWT
- `BORG_PASSPHRASE`: Passphrase de chiffrement des sauvegardes

### 1.2 Generation des cles SSH

```bash
./generate-ssh-keys.sh
```

Cree une paire de cles RSA 4096 bits pour l'authentification sans mot de passe.

### 1.3 Demarrage de l'application

```bash
# Construire et demarrer tous les conteneurs
docker-compose up -d

# Verifier le statut
docker-compose ps

# Consulter les logs
docker-compose logs -f ghostfolio
```

### 1.4 Verification

Accedez a http://localhost:3333 pour verifier que Ghostfolio fonctionne.

---

## Etape 2: Conception de l'architecture de sauvegarde

### Principes de securite appliques

1. **Chiffrement cote client**: Les donnees sont chiffrees par `borg-client` AVANT d'etre envoyees au serveur. Le serveur ne voit jamais les donnees en clair.

2. **Isolation reseau**: Le `borg-server` est sur un reseau `internal: true`, sans acces a Internet ni aux conteneurs applicatifs.

3. **Authentification par cle SSH**: Aucun mot de passe n'est utilise pour la connexion SSH, uniquement des cles cryptographiques.

4. **Separation des privileges**:
   - `borg-client` a acces en lecture seule aux donnees
   - `borg-server` n'a aucun acces aux donnees sources

5. **Secrets non versions**: Le fichier `.env` et les cles SSH sont exclus de Git via `.gitignore`.

### Flux de sauvegarde

```
1. borg-client execute pg_dump sur PostgreSQL
2. Le dump est stocke temporairement dans /tmp/backup
3. borg-client chiffre et compresse les donnees
4. Les donnees chiffrees sont envoyees via SSH au borg-server
5. borg-server stocke les blocs chiffres (deduplication)
6. Le repertoire temporaire est nettoye
```

---

## Etape 3: Mise en place du serveur borg-server

### Configuration (borg-server/Dockerfile)

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    openssh-server \
    borgbackup

# Securisation SSH
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# Utilisateur dedie
RUN useradd -m -d /home/borg -s /bin/bash borg
RUN mkdir -p /var/borg/repos && chown -R borg:borg /var/borg
```

### Points cles de securite

- **PasswordAuthentication no**: Seule l'authentification par cle est permise
- **PermitRootLogin no**: Connexion root interdite
- **Utilisateur dedie**: L'utilisateur `borg` a des privileges limites

---

## Etape 4: Mise en place du conteneur borg-client

### Configuration (borg-client/Dockerfile)

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    borgbackup \
    openssh-client \
    postgresql-client

# Configuration SSH
RUN echo "Host borg-server" > /root/.ssh/config
RUN echo "    StrictHostKeyChecking accept-new" >> /root/.ssh/config
```

### Scripts disponibles

| Script | Description |
|--------|-------------|
| `init-repo.sh` | Initialise le depot BorgBackup |
| `backup.sh` | Execute une sauvegarde complete |
| `restore.sh` | Restaure une archive |
| `list-backups.sh` | Liste les archives disponibles |
| `simulate-attack.sh` | Simule une attaque ransomware |

---

## Etape 5: Execution d'une sauvegarde complete

### 5.1 Initialisation du depot

```bash
# Acceder au client
docker exec -it borg-client bash

# Initialiser le depot (une seule fois)
./init-repo.sh
```

Sortie attendue:
```
[INFO] Test de connexion SSH...
Connexion SSH OK
[INFO] Initialisation du depot avec chiffrement...
[OK] Depot initialise avec succes
```

### 5.2 Premiere sauvegarde

```bash
./backup.sh
```

Sortie attendue:
```
==============================================
 Sauvegarde Ghostfolio - ghostfolio-2024-01-15_10-30-00
==============================================
[INFO] Dump de la base de donnees PostgreSQL...
[OK] Dump PostgreSQL cree: ghostfolio.dump
[INFO] Creation de l'archive BorgBackup...
[OK] Archive creee avec succes
[INFO] Application de la politique de retention...
==============================================
 Sauvegarde terminee avec succes
==============================================
```

### 5.3 Verification

```bash
./list-backups.sh
```

---

## Etape 6: Scenario d'attaque (simulation)

### Contexte

Un ransomware a chiffre les donnees Ghostfolio. L'application est inutilisable.

### Simulation

```bash
# Dans le conteneur borg-client
./simulate-attack.sh
```

Ce script:
1. Vide toutes les tables de la base de donnees
2. Insere un message de rancon
3. Rend l'application inutilisable

### Verification de l'attaque

```bash
# L'application ne repond plus correctement
curl http://localhost:3333

# Dans la base, on voit le message de rancon
docker exec -it postgres psql -U ghostfolio -d ghostfolio -c "SELECT * FROM ransom_note;"
```

---

## Etape 7: Restauration complete

### 7.1 Lister les archives disponibles

```bash
docker exec -it borg-client ./list-backups.sh
```

### 7.2 Restaurer une archive

```bash
docker exec -it borg-client bash

# Restaurer la derniere archive
./restore.sh $(borg list --short --last 1 $BORG_REPO)

# OU specifier une archive precise
./restore.sh ghostfolio-2024-01-15_10-30-00
```

### 7.3 Redemarrer l'application

```bash
docker-compose restart ghostfolio
```

### 7.4 Verification

```bash
# L'application fonctionne a nouveau
curl http://localhost:3333
```

---

## Etape 8: Mise en place de la rotation et automatisation

### Politique de retention

La politique definie dans `backup.sh`:

| Type | Retention | Description |
|------|-----------|-------------|
| Journalier | 7 | Garde les 7 dernieres sauvegardes journalieres |
| Hebdomadaire | 4 | Garde 4 sauvegardes hebdomadaires |
| Mensuel | 6 | Garde 6 sauvegardes mensuelles |

```bash
borg prune \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=6 \
    "$BORG_REPO"
```

### Automatisation avec cron

#### Option 1: Cron dans le conteneur

Ajoutez au Dockerfile du borg-client:

```dockerfile
# Ajout de la tache cron
RUN echo "0 2 * * * /backup-scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/backup
RUN chmod 0644 /etc/cron.d/backup
RUN crontab /etc/cron.d/backup
```

#### Option 2: Cron sur l'hote

```bash
# Ajouter a crontab de l'hote
0 2 * * * docker exec borg-client /backup-scripts/backup.sh >> /var/log/ghostfolio-backup.log 2>&1
```

### Verification de l'automatisation

```bash
# Verifier les logs
tail -f /var/log/backup.log

# Verifier la derniere sauvegarde
docker exec -it borg-client ./list-backups.sh
```

---

## Resume des commandes

### Demarrage initial

```bash
./generate-secrets.sh
./generate-ssh-keys.sh
docker-compose up -d
docker exec -it borg-client ./init-repo.sh
```

### Sauvegarde manuelle

```bash
docker exec -it borg-client ./backup.sh
```

### Restauration

```bash
docker exec -it borg-client ./list-backups.sh
docker exec -it borg-client ./restore.sh <nom_archive>
docker-compose restart ghostfolio
```

### Verification

```bash
docker-compose ps
docker exec -it borg-client ./list-backups.sh
curl http://localhost:3333
```

---

## Checklist de conformite

- [x] Aucun mot de passe en clair dans les fichiers versiones
- [x] Serveur de sauvegarde isole (reseau interne)
- [x] Chiffrement cote client (repokey-blake2)
- [x] Application destructible et restaurable
- [x] Fonctionnement apres reinstallation de Ghostfolio
- [x] Plan de retention documente (7/4/6)
- [x] Actions reproductibles et documentees
