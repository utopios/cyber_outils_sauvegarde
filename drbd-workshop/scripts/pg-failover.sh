#!/bin/bash
# =============================================================================
# Script de Failover PostgreSQL sur DRBD
# =============================================================================
# Gere le failover de PostgreSQL utilisant DRBD comme stockage.
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DRBD_ROLE_FILE="/var/lib/drbd/role"
DRBD_MOUNT="/mnt/drbd"
PG_DATA="$DRBD_MOUNT/pgdata"
PG_USER="postgres"

show_help() {
    cat << EOF

Usage: $0 <command>

Commands:
    start               Demarrer PostgreSQL (si Primary)
    stop                Arreter PostgreSQL proprement
    status              Voir le status de PostgreSQL
    failover            Effectuer un failover complet
    takeover            Prendre le controle de PostgreSQL
    init                Initialiser une nouvelle base PostgreSQL

Examples:
    $0 start            # Demarrer PostgreSQL
    $0 failover         # Failover planifie
    $0 takeover         # Prendre le controle apres panne

EOF
}

check_drbd_role() {
    cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown"
}

check_pg_running() {
    pgrep -x postgres &>/dev/null
    return $?
}

check_mounted() {
    mountpoint -q "$DRBD_MOUNT" 2>/dev/null
    return $?
}

init_postgresql() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           INITIALISATION POSTGRESQL SUR DRBD              ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ROLE=$(check_drbd_role)
    if [ "$ROLE" != "primary" ]; then
        echo -e "${RED}[ERROR] Ce noeud doit etre PRIMARY pour initialiser PostgreSQL${NC}"
        exit 1
    fi

    if ! check_mounted; then
        echo -e "${RED}[ERROR] DRBD n'est pas monte sur $DRBD_MOUNT${NC}"
        echo "Montez d'abord: mount /dev/drbd0 $DRBD_MOUNT"
        exit 1
    fi

    if [ -d "$PG_DATA" ] && [ -f "$PG_DATA/PG_VERSION" ]; then
        echo -e "${YELLOW}[WARN] PostgreSQL semble deja initialise${NC}"
        read -p "Reinitialiser? ATTENTION: Donnees perdues! (yes/no) " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Operation annulee."
            exit 0
        fi
        rm -rf "$PG_DATA"
    fi

    echo -e "${GREEN}[1/4] Creation du repertoire de donnees...${NC}"
    mkdir -p "$PG_DATA"
    chown -R $PG_USER:$PG_USER "$PG_DATA"
    chmod 700 "$PG_DATA"

    echo -e "${GREEN}[2/4] Initialisation du cluster PostgreSQL...${NC}"
    su - $PG_USER -c "initdb -D $PG_DATA" || {
        echo -e "${RED}[ERROR] Echec de l'initialisation${NC}"
        exit 1
    }

    echo -e "${GREEN}[3/4] Configuration de PostgreSQL...${NC}"
    cat >> "$PG_DATA/postgresql.conf" << EOF

# Configuration pour cluster DRBD
listen_addresses = '*'
port = 5432
max_connections = 100

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'

# Performance
shared_buffers = 128MB
work_mem = 4MB
EOF

    cat >> "$PG_DATA/pg_hba.conf" << EOF

# Acces reseau pour le cluster
host    all    all    172.28.0.0/16    md5
host    all    all    0.0.0.0/0        md5
EOF

    echo -e "${GREEN}[4/4] Demarrage de PostgreSQL...${NC}"
    su - $PG_USER -c "pg_ctl -D $PG_DATA start"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  POSTGRESQL INITIALISE AVEC SUCCES                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Base de donnees prete sur $PG_DATA"
    echo ""
    echo "Pour creer une base de test:"
    echo "  su - postgres -c \"createdb testdb\""
}

start_postgresql() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Demarrage de PostgreSQL${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    ROLE=$(check_drbd_role)
    if [ "$ROLE" != "primary" ]; then
        echo -e "${RED}[ERROR] Ce noeud doit etre PRIMARY pour demarrer PostgreSQL${NC}"
        echo "Role actuel: $ROLE"
        exit 1
    fi

    if ! check_mounted; then
        echo -e "${YELLOW}[INFO] Montage de DRBD...${NC}"
        mount /dev/drbd0 "$DRBD_MOUNT" 2>/dev/null || {
            echo -e "${RED}[ERROR] Impossible de monter DRBD${NC}"
            exit 1
        }
    fi

    if [ ! -d "$PG_DATA" ]; then
        echo -e "${RED}[ERROR] Repertoire de donnees PostgreSQL non trouve${NC}"
        echo "Initialisez d'abord: $0 init"
        exit 1
    fi

    if check_pg_running; then
        echo -e "${YELLOW}[WARN] PostgreSQL est deja en cours d'execution${NC}"
        return 0
    fi

    echo -e "${GREEN}[INFO] Demarrage de PostgreSQL...${NC}"
    su - $PG_USER -c "pg_ctl -D $PG_DATA start"

    sleep 2

    if check_pg_running; then
        echo ""
        echo -e "${GREEN}[SUCCESS] PostgreSQL demarre${NC}"
        echo ""
        echo "Connexion: psql -h localhost -U postgres"
    else
        echo -e "${RED}[ERROR] Echec du demarrage${NC}"
        echo "Verifiez les logs: $PG_DATA/log/"
        exit 1
    fi
}

stop_postgresql() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Arret de PostgreSQL${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if ! check_pg_running; then
        echo -e "${YELLOW}[WARN] PostgreSQL n'est pas en cours d'execution${NC}"
        return 0
    fi

    echo -e "${GREEN}[INFO] Arret de PostgreSQL (mode smart)...${NC}"
    su - $PG_USER -c "pg_ctl -D $PG_DATA stop -m smart" 2>/dev/null || {
        echo -e "${YELLOW}[WARN] Arret smart echoue, tentative fast...${NC}"
        su - $PG_USER -c "pg_ctl -D $PG_DATA stop -m fast" 2>/dev/null || {
            echo -e "${RED}[WARN] Arret fast echoue, tentative immediate...${NC}"
            su - $PG_USER -c "pg_ctl -D $PG_DATA stop -m immediate"
        }
    }

    sleep 2

    if ! check_pg_running; then
        echo -e "${GREEN}[SUCCESS] PostgreSQL arrete${NC}"
    else
        echo -e "${RED}[ERROR] PostgreSQL ne s'est pas arrete${NC}"
        exit 1
    fi
}

show_pg_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           STATUS POSTGRESQL                               ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ROLE=$(check_drbd_role)
    echo "DRBD Role: $ROLE"
    echo "DRBD Mount: $(check_mounted && echo 'Mounted' || echo 'Not Mounted')"
    echo ""

    if check_pg_running; then
        echo -e "PostgreSQL: ${GREEN}Running${NC}"
        echo ""
        echo "Informations:"
        su - $PG_USER -c "pg_ctl -D $PG_DATA status" 2>/dev/null || echo "  (details non disponibles)"
        echo ""
        echo "Bases de donnees:"
        su - $PG_USER -c "psql -c '\l'" 2>/dev/null || echo "  (impossible de lister)"
    else
        echo -e "PostgreSQL: ${RED}Stopped${NC}"
    fi
}

do_failover() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           FAILOVER POSTGRESQL SUR DRBD                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ROLE=$(check_drbd_role)
    if [ "$ROLE" != "primary" ]; then
        echo -e "${RED}[ERROR] Ce noeud doit etre PRIMARY pour initier un failover${NC}"
        echo "Utilisez 'takeover' pour prendre le controle depuis un Secondary"
        exit 1
    fi

    echo -e "${YELLOW}[WARN] Cette operation va:${NC}"
    echo "  1. Arreter PostgreSQL"
    echo "  2. Demonter DRBD"
    echo "  3. Passer ce noeud en Secondary"
    echo ""
    echo "L'autre noeud devra prendre le relais avec 'takeover'"
    echo ""

    read -p "Continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation annulee."
        exit 0
    fi

    echo ""
    echo -e "${GREEN}[1/4] Arret de PostgreSQL...${NC}"
    stop_postgresql

    echo ""
    echo -e "${GREEN}[2/4] Synchronisation des donnees...${NC}"
    sync
    sleep 2

    echo ""
    echo -e "${GREEN}[3/4] Demontage de DRBD...${NC}"
    umount "$DRBD_MOUNT" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}[4/4] Passage en Secondary...${NC}"
    /scripts/drbd-role.sh secondary

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  FAILOVER COMPLETE                                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Sur l'autre noeud, executez:"
    echo "  /scripts/pg-failover.sh takeover"
}

do_takeover() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           TAKEOVER POSTGRESQL                             ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ROLE=$(check_drbd_role)
    if [ "$ROLE" == "primary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja PRIMARY${NC}"
        echo "Demarrage de PostgreSQL..."
        start_postgresql
        return 0
    fi

    echo -e "${GREEN}[1/4] Promotion en Primary DRBD...${NC}"
    /scripts/drbd-role.sh primary

    echo ""
    echo -e "${GREEN}[2/4] Montage de DRBD...${NC}"
    mkdir -p "$DRBD_MOUNT"
    mount /dev/drbd0 "$DRBD_MOUNT" 2>/dev/null || {
        echo -e "${YELLOW}[INFO] Simulation de montage...${NC}"
    }

    echo ""
    echo -e "${GREEN}[3/4] Verification des donnees PostgreSQL...${NC}"
    if [ ! -d "$PG_DATA" ]; then
        echo -e "${YELLOW}[WARN] Donnees PostgreSQL non trouvees${NC}"
        echo "Initialisez avec: $0 init"
        return 1
    fi

    echo ""
    echo -e "${GREEN}[4/4] Demarrage de PostgreSQL...${NC}"
    start_postgresql

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  TAKEOVER COMPLETE                                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "PostgreSQL est maintenant operationnel sur ce noeud."
}

# Main
case "${1:-help}" in
    start)
        start_postgresql
        ;;
    stop)
        stop_postgresql
        ;;
    status)
        show_pg_status
        ;;
    failover)
        do_failover
        ;;
    takeover)
        do_takeover
        ;;
    init)
        init_postgresql
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Commande inconnue: $1${NC}"
        show_help
        exit 1
        ;;
esac
