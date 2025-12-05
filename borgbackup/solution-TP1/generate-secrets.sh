#!/bin/bash
#===============================================================================
# Script de generation des secrets pour Ghostfolio et BorgBackup
# Ce script genere un fichier .env avec des secrets cryptographiquement securises
#===============================================================================
set -e

ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

echo "=============================================="
echo " Generation des secrets"
echo "=============================================="

# Verification si .env existe deja
if [ -f "$ENV_FILE" ]; then
    echo "[WARN] Le fichier $ENV_FILE existe deja!"
    read -p "Voulez-vous le remplacer? (oui/non): " CONFIRM
    if [ "$CONFIRM" != "oui" ]; then
        echo "[INFO] Generation annulee"
        exit 0
    fi
    # Backup de l'ancien fichier
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "[INFO] Ancien fichier sauvegarde"
fi

# Generation des secrets
echo "[INFO] Generation des secrets cryptographiques..."

POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
ACCESS_TOKEN_SALT=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)
BORG_PASSPHRASE=$(openssl rand -base64 32 | tr -d '/+=')

# Creation du fichier .env
cat > "$ENV_FILE" << EOF
# ===========================================
# Configuration Ghostfolio
# Genere automatiquement le $(date)
# ===========================================

# PostgreSQL
POSTGRES_USER=ghostfolio
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=ghostfolio

# Ghostfolio Secrets
ACCESS_TOKEN_SALT=${ACCESS_TOKEN_SALT}
JWT_SECRET_KEY=${JWT_SECRET_KEY}

# ===========================================
# Configuration BorgBackup
# ===========================================
BORG_PASSPHRASE=${BORG_PASSPHRASE}
EOF

# Securisation du fichier
chmod 600 "$ENV_FILE"

echo "[OK] Fichier $ENV_FILE cree"
echo ""
echo "=============================================="
echo " Secrets generes avec succes"
echo "=============================================="
echo ""
echo "[IMPORTANT] Conservez une copie securisee de:"
echo "            - BORG_PASSPHRASE (necessaire pour restaurer les sauvegardes)"
echo "            - Le fichier .env complet"
echo ""
echo "[SECURITE] Le fichier .env a les permissions 600 (lecture/ecriture proprietaire uniquement)"
echo ""
echo "[NEXT] Generez les cles SSH: ./generate-ssh-keys.sh"
