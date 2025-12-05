#!/bin/bash
#===============================================================================
# Script de restauration complete de Ghostfolio
# Restaure une archive BorgBackup et reimporte les donnees PostgreSQL
#===============================================================================
set -e

# Configuration
BORG_SERVER="${BORG_SERVER:-borg-server}"
BORG_USER="${BORG_USER:-borg}"
BORG_REPO="ssh://${BORG_USER}@${BORG_SERVER}/var/borg/repos/ghostfolio"

POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-ghostfolio}"
POSTGRES_DB="${POSTGRES_DB:-ghostfolio}"

RESTORE_DIR="/tmp/restore"

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
echo " Restauration Ghostfolio"
echo "=============================================="
echo "[INFO] Date: $(date)"
echo "[INFO] Depot: $BORG_REPO"
echo ""

# Afficher les archives disponibles
echo "[INFO] Archives disponibles:"
borg list "$BORG_REPO"
echo ""

# Selection de l'archive
if [ -z "$1" ]; then
    echo "[INFO] Utilisation: $0 <nom_archive>"
    echo "       Exemple: $0 ghostfolio-2024-01-15_10-30-00"
    echo ""
    echo "[INFO] Pour restaurer la derniere archive, utilisez:"
    echo "       $0 \$(borg list --short --last 1 $BORG_REPO)"
    exit 1
fi

ARCHIVE_NAME="$1"
echo "[INFO] Archive selectionnee: $ARCHIVE_NAME"
echo ""

# Confirmation
read -p "[ATTENTION] Cette operation va ecraser les donnees actuelles. Continuer? (oui/non): " CONFIRM
if [ "$CONFIRM" != "oui" ]; then
    echo "[INFO] Restauration annulee"
    exit 0
fi

# Preparation du repertoire de restauration
echo ""
echo "[INFO] Preparation du repertoire de restauration..."
rm -rf "${RESTORE_DIR:?}"
mkdir -p "$RESTORE_DIR"

# Extraction de l'archive
echo "[INFO] Extraction de l'archive..."
cd "$RESTORE_DIR"
borg extract --progress "$BORG_REPO::$ARCHIVE_NAME"

# Localisation du dump
DUMP_FILE=$(find "$RESTORE_DIR" -name "ghostfolio.dump" -type f | head -1)
if [ -z "$DUMP_FILE" ]; then
    echo "[ERREUR] Fichier ghostfolio.dump non trouve dans l'archive"
    exit 1
fi

echo "[OK] Dump trouve: $DUMP_FILE"

# Affichage des metadonnees si disponibles
INFO_FILE=$(find "$RESTORE_DIR" -name "backup-info.txt" -type f | head -1)
if [ -n "$INFO_FILE" ]; then
    echo ""
    echo "[INFO] Metadonnees de la sauvegarde:"
    cat "$INFO_FILE"
    echo ""
fi

# Restauration de la base de donnees
echo "[INFO] Restauration de la base de donnees PostgreSQL..."
echo "       Host: $POSTGRES_HOST"
echo "       Database: $POSTGRES_DB"
echo "       User: $POSTGRES_USER"
echo ""

# Suppression et recreation de la base
echo "[INFO] Suppression de la base existante..."
psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB;"

echo "[INFO] Creation d'une nouvelle base..."
psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

echo "[INFO] Restauration des donnees..."
pg_restore -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges "$DUMP_FILE"

echo "[OK] Base de donnees restauree"

# Nettoyage
echo ""
echo "[INFO] Nettoyage..."
rm -rf "${RESTORE_DIR:?}"

echo ""
echo "=============================================="
echo " Restauration terminee avec succes"
echo "=============================================="
echo "[INFO] Archive restauree: $ARCHIVE_NAME"
echo "[INFO] Date: $(date)"
echo ""
echo "[IMPORTANT] Redemarrez l'application Ghostfolio:"
echo "            docker-compose restart ghostfolio"
