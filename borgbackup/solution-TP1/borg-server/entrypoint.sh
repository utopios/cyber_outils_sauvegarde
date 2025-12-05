#!/bin/bash
set -e

echo "[INFO] Configuration du serveur Borg..."

# Configuration des cles SSH autorisees
if [ -f /home/borg/.ssh/authorized_keys ]; then
    chmod 600 /home/borg/.ssh/authorized_keys
    chown borg:borg /home/borg/.ssh/authorized_keys
    echo "[INFO] Cles SSH autorisees configurees"
else
    echo "[WARN] Aucune cle SSH trouvee - le client ne pourra pas se connecter"
    echo "[WARN] Assurez-vous de generer les cles avec: ./generate-ssh-keys.sh"
fi

# Verification des permissions sur le repertoire borg
chown -R borg:borg /var/borg
chmod 755 /var/borg
chmod 700 /var/borg/repos

echo "[INFO] Demarrage du serveur SSH sur le port 22..."
exec "$@"
