#!/bin/bash
#===============================================================================
# Script de generation des cles SSH pour BorgBackup
# Ces cles permettent au client de se connecter au serveur sans mot de passe
#===============================================================================
set -e

CLIENT_SSH_DIR="./borg-client/ssh-keys"
SERVER_SSH_DIR="./borg-server/ssh-keys"

echo "=============================================="
echo " Generation des cles SSH"
echo "=============================================="

# Creation des repertoires
mkdir -p "$CLIENT_SSH_DIR"
mkdir -p "$SERVER_SSH_DIR"

# Verification si les cles existent deja
if [ -f "$CLIENT_SSH_DIR/id_rsa" ]; then
    echo "[WARN] Les cles SSH existent deja!"
    read -p "Voulez-vous les regenerer? (oui/non): " CONFIRM
    if [ "$CONFIRM" != "oui" ]; then
        echo "[INFO] Generation annulee"
        exit 0
    fi
fi

# Generation de la paire de cles
echo "[INFO] Generation de la paire de cles RSA 4096 bits..."
ssh-keygen -t rsa -b 4096 -f "$CLIENT_SSH_DIR/id_rsa" -N "" -C "borg-backup-client"

# Configuration des permissions
chmod 600 "$CLIENT_SSH_DIR/id_rsa"
chmod 644 "$CLIENT_SSH_DIR/id_rsa.pub"

# Copie de la cle publique pour le serveur
echo "[INFO] Configuration du serveur..."
cp "$CLIENT_SSH_DIR/id_rsa.pub" "$SERVER_SSH_DIR/authorized_keys"
chmod 644 "$SERVER_SSH_DIR/authorized_keys"

echo ""
echo "=============================================="
echo " Cles SSH generees avec succes"
echo "=============================================="
echo ""
echo "Fichiers crees:"
echo "  - $CLIENT_SSH_DIR/id_rsa           (cle privee client)"
echo "  - $CLIENT_SSH_DIR/id_rsa.pub       (cle publique client)"
echo "  - $SERVER_SSH_DIR/authorized_keys  (cles autorisees serveur)"
echo ""
echo "[SECURITE] La cle privee ne doit JAMAIS etre partagee!"
echo ""
echo "[NEXT] Demarrez l'environnement: docker-compose up -d"
