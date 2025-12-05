#!/bin/bash
#===============================================================================
# Script de sauvegarde complete de Ghostfolio
# Effectue un dump PostgreSQL et sauvegarde les donnees avec BorgBackup
#===============================================================================
set -e

# Configuration
BORG_SERVER="${BORG_SERVER:-borg-server}"
BORG_USER="${BORG_USER:-borg}"
BORG_REPO="ssh://${BORG_USER}@${BORG_SERVER}/var/borg/repos/ghostfolio"

POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-ghostfolio}"
POSTGRES_DB="${POSTGRES_DB:-ghostfolio}"

BACKUP_DIR="/tmp/backup"
ARCHIVE_NAME="ghostfolio-$(date +'%Y-%m-%d_%H-%M-%S')"

# Verification des variables requises
if [ -z "$BORG_PASSPHRASE" ]; then
    echo "[ERREUR] BORG_PASSPHRASE n'est pas definie!"
    exit 1
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "[ERREUR] POSTGRES_PASSWORD n'est pas definie!"
    exit 1
fi

export BORG_REPO
export BORG_PASSPHRASE
export PGPASSWORD="$POSTGRES_PASSWORD"

echo "=============================================="
echo " Sauvegarde Ghostfolio - $ARCHIVE_NAME"
echo "=============================================="
echo "[INFO] Date: $(date)"
echo "[INFO] Depot: $BORG_REPO"
echo ""

# Nettoyage du repertoire de staging
echo "[INFO] Preparation du repertoire de staging..."
rm -rf "${BACKUP_DIR:?}"/*
mkdir -p "$BACKUP_DIR"

# Dump PostgreSQL
echo "[INFO] Dump de la base de donnees PostgreSQL..."
echo "       Host: $POSTGRES_HOST"
echo "       Database: $POSTGRES_DB"
echo "       User: $POSTGRES_USER"

if pg_dump -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c -f "$BACKUP_DIR/ghostfolio.dump"; then
    echo "[OK] Dump PostgreSQL cree: ghostfolio.dump"
    ls -lh "$BACKUP_DIR/ghostfolio.dump"
else
    echo "[ERREUR] Echec du dump PostgreSQL"
    exit 1
fi

# Sauvegarde des metadonnees
echo ""
echo "[INFO] Creation des metadonnees..."
cat > "$BACKUP_DIR/backup-info.txt" << EOF
Sauvegarde Ghostfolio
=====================
Date: $(date)
Archive: $ARCHIVE_NAME
PostgreSQL Host: $POSTGRES_HOST
PostgreSQL Database: $POSTGRES_DB
PostgreSQL User: $POSTGRES_USER
Borg Repository: $BORG_REPO
EOF

echo "[OK] Metadonnees creees"

# Creation de l'archive Borg
echo ""
echo "[INFO] Creation de l'archive BorgBackup..."
borg create \
    --stats \
    --show-rc \
    --compression zstd,3 \
    --exclude-caches \
    "$BORG_REPO::$ARCHIVE_NAME" \
    "$BACKUP_DIR"

echo ""
echo "[OK] Archive creee avec succes"

# Application de la politique de retention
echo ""
echo "[INFO] Application de la politique de retention..."
echo "       - Garder 7 sauvegardes journalieres"
echo "       - Garder 4 sauvegardes hebdomadaires"
echo "       - Garder 6 sauvegardes mensuelles"
echo ""

borg prune \
    --stats \
    --show-rc \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=6 \
    "$BORG_REPO"

# Compactage du depot
echo ""
echo "[INFO] Compactage du depot..."
borg compact "$BORG_REPO"

# Nettoyage
echo ""
echo "[INFO] Nettoyage du repertoire de staging..."
rm -rf "${BACKUP_DIR:?}"/*

# Affichage des archives
echo ""
echo "[INFO] Archives disponibles:"
borg list "$BORG_REPO"

echo ""
echo "=============================================="
echo " Sauvegarde terminee avec succes"
echo "=============================================="
echo "[INFO] Archive: $ARCHIVE_NAME"
echo "[INFO] Date: $(date)"
