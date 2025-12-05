#!/bin/bash
set -e

echo "[INFO] Configuration du client Borg..."

# Configuration des permissions de la cle SSH privee
if [ -f /root/.ssh/id_rsa ]; then
    chmod 600 /root/.ssh/id_rsa
    echo "[INFO] Cle SSH privee configuree"
else
    echo "[WARN] Cle SSH privee non trouvee dans /root/.ssh/id_rsa"
    echo "[WARN] Executez ./generate-ssh-keys.sh pour generer les cles"
fi

if [ -f /root/.ssh/id_rsa.pub ]; then
    chmod 644 /root/.ssh/id_rsa.pub
fi

# Verification de la passphrase Borg
if [ -z "$BORG_PASSPHRASE" ]; then
    echo "[WARN] BORG_PASSPHRASE n'est pas definie!"
    echo "[WARN] Les sauvegardes chiffrees necessitent cette variable"
fi

echo "[INFO] Client Borg pret"
echo "[INFO] Scripts disponibles:"
echo "       - ./backup.sh      : Effectuer une sauvegarde"
echo "       - ./restore.sh     : Restaurer une sauvegarde"
echo "       - ./init-repo.sh   : Initialiser le depot Borg"
echo "       - ./list-backups.sh: Lister les archives"

exec "$@"
