#!/bin/bash
#===============================================================================
# Script d'initialisation du depot BorgBackup
# Ce script initialise un nouveau depot chiffre sur le serveur de sauvegarde
#===============================================================================
set -e

# Configuration
BORG_SERVER="${BORG_SERVER:-borg-server}"
BORG_USER="${BORG_USER:-borg}"
BORG_REPO="ssh://${BORG_USER}@${BORG_SERVER}/var/borg/repos/ghostfolio"

# Verification de la passphrase
if [ -z "$BORG_PASSPHRASE" ]; then
    echo "[ERREUR] BORG_PASSPHRASE n'est pas definie!"
    echo "         Definissez cette variable dans le fichier .env"
    exit 1
fi

export BORG_REPO
export BORG_PASSPHRASE

echo "=============================================="
echo " Initialisation du depot BorgBackup"
echo "=============================================="
echo "[INFO] Serveur: $BORG_SERVER"
echo "[INFO] Depot: $BORG_REPO"
echo ""

# Test de connexion SSH
echo "[INFO] Test de connexion SSH..."
if ! ssh -o ConnectTimeout=10 ${BORG_USER}@${BORG_SERVER} "echo 'Connexion SSH OK'"; then
    echo "[ERREUR] Impossible de se connecter au serveur de sauvegarde"
    echo "         Verifiez que les cles SSH sont correctement configurees"
    exit 1
fi

# Initialisation du depot avec chiffrement repokey
echo ""
echo "[INFO] Initialisation du depot avec chiffrement..."
if borg init --encryption=repokey-blake2 "$BORG_REPO" 2>/dev/null; then
    echo "[OK] Depot initialise avec succes"
    echo ""
    echo "[IMPORTANT] Exportez la cle du depot pour la recuperation d'urgence:"
    echo "            borg key export $BORG_REPO /backup-scripts/borg-key-backup.txt"
else
    echo "[INFO] Le depot existe deja ou une erreur s'est produite"
    # Verification que le depot est accessible
    if borg info "$BORG_REPO" > /dev/null 2>&1; then
        echo "[OK] Le depot existant est accessible"
    else
        echo "[ERREUR] Impossible d'acceder au depot"
        exit 1
    fi
fi

echo ""
echo "[INFO] Informations du depot:"
borg info "$BORG_REPO"

echo ""
echo "=============================================="
echo " Initialisation terminee"
echo "=============================================="
