#!/bin/bash
#===============================================================================
# Script de liste des sauvegardes disponibles
#===============================================================================
set -e

# Configuration
BORG_SERVER="${BORG_SERVER:-borg-server}"
BORG_USER="${BORG_USER:-borg}"
BORG_REPO="ssh://${BORG_USER}@${BORG_SERVER}/var/borg/repos/ghostfolio"

if [ -z "$BORG_PASSPHRASE" ]; then
    echo "[ERREUR] BORG_PASSPHRASE n'est pas definie!"
    exit 1
fi

export BORG_REPO
export BORG_PASSPHRASE

echo "=============================================="
echo " Liste des sauvegardes Ghostfolio"
echo "=============================================="
echo "[INFO] Depot: $BORG_REPO"
echo ""

# Liste des archives
echo "[INFO] Archives disponibles:"
echo ""
borg list "$BORG_REPO"

echo ""
echo "=============================================="
echo " Informations du depot"
echo "=============================================="
borg info "$BORG_REPO"
