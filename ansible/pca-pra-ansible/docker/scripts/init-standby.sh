#!/bin/bash
# Script d'initialisation du standby PostgreSQL
# Ce script configure la réplication streaming depuis le primary

set -e

PGDATA="${PGDATA:-/var/lib/postgresql/data/pgdata}"
PRIMARY_HOST="${POSTGRES_PRIMARY_HOST:-192.168.56.10}"
PRIMARY_PORT="${POSTGRES_PRIMARY_PORT:-5432}"
REPLICATION_USER="${POSTGRES_REPLICATION_USER:-replicator}"
REPLICATION_PASSWORD="${POSTGRES_REPLICATION_PASSWORD:-R3pl1c@t0r!}"

echo "=== Initialisation du PostgreSQL Standby ==="

# Vérifier si le répertoire de données existe déjà
if [ -f "$PGDATA/PG_VERSION" ]; then
    echo "Base de données existante détectée, vérification du mode standby..."

    if [ -f "$PGDATA/standby.signal" ]; then
        echo "Mode standby déjà configuré."
        exit 0
    fi
fi

# Attendre que le primary soit disponible
echo "Attente du primary PostgreSQL sur $PRIMARY_HOST:$PRIMARY_PORT..."
until PGPASSWORD="$REPLICATION_PASSWORD" pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$REPLICATION_USER"; do
    echo "Primary non disponible, nouvelle tentative dans 5 secondes..."
    sleep 5
done

echo "Primary disponible, démarrage de la synchronisation..."

# Nettoyer le répertoire de données
rm -rf "$PGDATA"/*

# Faire un base backup depuis le primary
echo "Exécution de pg_basebackup..."
PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
    -h "$PRIMARY_HOST" \
    -p "$PRIMARY_PORT" \
    -U "$REPLICATION_USER" \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -P \
    -R \
    -S lyon_replica

# Créer le fichier standby.signal pour PostgreSQL 12+
touch "$PGDATA/standby.signal"

# Configurer les paramètres de réplication dans postgresql.auto.conf
cat >> "$PGDATA/postgresql.auto.conf" << EOF

# Configuration de réplication standby
primary_conninfo = 'host=$PRIMARY_HOST port=$PRIMARY_PORT user=$REPLICATION_USER password=$REPLICATION_PASSWORD application_name=lyon_standby'
primary_slot_name = 'lyon_replica'
recovery_target_timeline = 'latest'
hot_standby = on
EOF

echo "=== Configuration du standby terminée ==="
echo "Le serveur va démarrer en mode hot standby."
