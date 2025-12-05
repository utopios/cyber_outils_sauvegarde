#!/bin/bash
#===============================================================================
# Script de simulation d'attaque ransomware (ETAPE 6 du TP)
# ATTENTION: Ce script detruit les donnees pour simuler une attaque!
#===============================================================================
set -e

# Configuration
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-ghostfolio}"
POSTGRES_DB="${POSTGRES_DB:-ghostfolio}"

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "[ERREUR] POSTGRES_PASSWORD n'est pas definie!"
    exit 1
fi

export PGPASSWORD="$POSTGRES_PASSWORD"

echo "=============================================="
echo " SIMULATION D'ATTAQUE RANSOMWARE"
echo "=============================================="
echo ""
echo "[ATTENTION] Ce script va DETRUIRE les donnees de l'application!"
echo "            Cette action simule une attaque ransomware."
echo ""

# Double confirmation
read -p "Etes-vous sur de vouloir continuer? (oui/non): " CONFIRM1
if [ "$CONFIRM1" != "oui" ]; then
    echo "[INFO] Simulation annulee"
    exit 0
fi

read -p "DERNIERE CHANCE - Confirmez la destruction des donnees (DETRUIRE/annuler): " CONFIRM2
if [ "$CONFIRM2" != "DETRUIRE" ]; then
    echo "[INFO] Simulation annulee"
    exit 0
fi

echo ""
echo "[ATTAQUE] Debut de l'attaque simulee..."
echo ""

# Phase 1: Corruption de la base de donnees
echo "[ATTAQUE] Phase 1: Corruption des tables..."
psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << EOF
-- Simulation: Suppression de toutes les donnees utilisateur
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' CASCADE';
    END LOOP;
END \$\$;
EOF

echo "[ATTAQUE] Tables videes"

# Phase 2: Message de rancon
echo ""
echo "[ATTAQUE] Phase 2: Insertion du message de rancon..."
psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << EOF
CREATE TABLE IF NOT EXISTS ransom_note (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO ransom_note (message) VALUES (
    'VOS DONNEES ONT ETE CHIFFREES! Envoyez 10 BTC a l''adresse xxx pour recuperer vos fichiers. - CryptoLocker Simulation'
);
EOF

echo ""
echo "=============================================="
echo " ATTAQUE SIMULEE TERMINEE"
echo "=============================================="
echo ""
echo "[INFO] Les donnees ont ete detruites."
echo "[INFO] L'application Ghostfolio est maintenant inutilisable."
echo ""
echo "[NEXT] Pour restaurer, utilisez:"
echo "       1. docker exec -it borg-client bash"
echo "       2. ./list-backups.sh"
echo "       3. ./restore.sh <nom_archive>"
echo "       4. docker-compose restart ghostfolio"
