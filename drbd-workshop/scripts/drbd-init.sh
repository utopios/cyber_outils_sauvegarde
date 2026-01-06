#!/bin/bash
# =============================================================================
# Script d'initialisation DRBD (Simulation)
# =============================================================================
# Ce script simule les commandes DRBD pour les besoins du workshop.
# En production, utilisez les vraies commandes drbdadm.
# =============================================================================

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_ROLE_FILE="/var/lib/drbd/role"
DRBD_SYNC_FILE="/var/lib/drbd/sync"
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"

# Creer le repertoire d'etat s'il n'existe pas
mkdir -p /var/lib/drbd

# Fonction d'aide
show_help() {
    cat << EOF

Usage: $0 <command> [options]

Commands:
    create-md           Creer les metadonnees DRBD sur le disque
    start               Demarrer le service DRBD
    stop                Arreter le service DRBD
    primary [--force]   Passer ce noeud en Primary
    secondary           Passer ce noeud en Secondary
    connect             Connecter au peer
    disconnect          Deconnecter du peer
    status              Afficher le status actuel
    help                Afficher cette aide

Examples:
    $0 create-md                 # Initialiser les metadonnees
    $0 start                     # Demarrer DRBD
    $0 primary --force           # Forcer en Primary (sync initiale)

EOF
}

# Creer les metadonnees
create_metadata() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Creation des metadonnees DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if [ -f "$DRBD_STATE_FILE" ]; then
        echo -e "${YELLOW}[WARN] Metadonnees existantes detectees${NC}"
        read -p "Voulez-vous les reinitialiser? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation annulee."
            return 0
        fi
    fi

    echo -e "${GREEN}[INFO] Verification du disque...${NC}"
    if [ -f /data/drbd-disk.img ]; then
        echo -e "${GREEN}[OK] Fichier disque trouve: /data/drbd-disk.img${NC}"
    else
        echo -e "${YELLOW}[INFO] Creation du fichier disque...${NC}"
        dd if=/dev/zero of=/data/drbd-disk.img bs=1M count=0 seek=1024 2>/dev/null
    fi

    echo -e "${GREEN}[INFO] Initialisation des metadonnees DRBD...${NC}"

    # Simuler la creation des metadonnees
    echo "unconfigured" > "$DRBD_STATE_FILE"
    echo "secondary" > "$DRBD_ROLE_FILE"
    echo "0" > "$DRBD_SYNC_FILE"
    echo "false" > "$DRBD_CONNECTED_FILE"

    echo ""
    echo -e "${GREEN}[SUCCESS] Metadonnees creees avec succes!${NC}"
    echo ""
    echo "  Resource: r0"
    echo "  Device: /dev/drbd0"
    echo "  Disk: /data/drbd-disk.img"
    echo "  Meta-disk: internal"
    echo ""
    echo -e "${YELLOW}Prochaine etape: $0 start${NC}"
}

# Demarrer DRBD
start_drbd() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Demarrage de DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if [ ! -f "$DRBD_STATE_FILE" ]; then
        echo -e "${RED}[ERROR] Metadonnees non initialisees!${NC}"
        echo "Executez d'abord: $0 create-md"
        exit 1
    fi

    echo -e "${GREEN}[INFO] Chargement du module DRBD... (simule)${NC}"
    sleep 1

    echo -e "${GREEN}[INFO] Configuration de la ressource r0...${NC}"
    echo "secondary" > "$DRBD_STATE_FILE"
    sleep 1

    echo -e "${GREEN}[INFO] Tentative de connexion au peer...${NC}"

    # Tester la connectivite avec le peer
    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
    fi

    if ping -c 1 -W 2 "$PEER_IP" &>/dev/null; then
        echo "true" > "$DRBD_CONNECTED_FILE"
        echo -e "${GREEN}[OK] Connexion au peer etablie${NC}"
    else
        echo "false" > "$DRBD_CONNECTED_FILE"
        echo -e "${YELLOW}[WARN] Peer non joignable - mode standalone${NC}"
    fi

    echo ""
    echo -e "${GREEN}[SUCCESS] DRBD demarre!${NC}"
    echo ""
    echo "  Role actuel: Secondary"
    echo "  Connexion: $(cat $DRBD_CONNECTED_FILE)"
    echo ""
    echo -e "${YELLOW}Pour voir le status: /scripts/drbd-status.sh${NC}"
}

# Arreter DRBD
stop_drbd() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Arret de DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo -e "${GREEN}[INFO] Deconnexion du peer...${NC}"
    echo "false" > "$DRBD_CONNECTED_FILE"

    echo -e "${GREEN}[INFO] Arret de la ressource r0...${NC}"
    echo "unconfigured" > "$DRBD_STATE_FILE"
    echo "secondary" > "$DRBD_ROLE_FILE"

    echo ""
    echo -e "${GREEN}[SUCCESS] DRBD arrete.${NC}"
}

# Passer en Primary
make_primary() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Passage en Primary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    FORCE=false
    if [ "$1" == "--force" ]; then
        FORCE=true
    fi

    CURRENT_ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")

    if [ "$CURRENT_ROLE" == "primary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja Primary${NC}"
        return 0
    fi

    CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")
    SYNC=$(cat "$DRBD_SYNC_FILE" 2>/dev/null || echo "0")

    if [ "$CONNECTED" == "false" ] && [ "$FORCE" != true ]; then
        echo -e "${RED}[ERROR] Peer non connecte!${NC}"
        echo "Utilisez --force pour forcer (risque de split-brain)"
        exit 1
    fi

    if [ "$SYNC" != "100" ] && [ "$FORCE" != true ]; then
        echo -e "${RED}[ERROR] Synchronisation incomplete ($SYNC%)${NC}"
        echo "Utilisez --force pour forcer"
        exit 1
    fi

    echo -e "${GREEN}[INFO] Promotion en Primary...${NC}"
    echo "primary" > "$DRBD_ROLE_FILE"

    if [ "$FORCE" == true ]; then
        echo -e "${YELLOW}[INFO] Mode force active - demarrage sync initiale...${NC}"
        echo "100" > "$DRBD_SYNC_FILE"
        echo "UpToDate" > "$DRBD_STATE_FILE"
    fi

    echo ""
    echo -e "${GREEN}[SUCCESS] Ce noeud est maintenant PRIMARY${NC}"
    echo ""
    echo "  Vous pouvez maintenant:"
    echo "  - Monter le filesystem: mount /dev/drbd0 /mnt/drbd"
    echo "  - Ou formatter d'abord: mkfs.ext4 /dev/drbd0"
    echo ""
}

# Passer en Secondary
make_secondary() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Passage en Secondary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    CURRENT_ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")

    if [ "$CURRENT_ROLE" == "secondary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja Secondary${NC}"
        return 0
    fi

    # Verifier si monte
    if mountpoint -q /mnt/drbd 2>/dev/null; then
        echo -e "${RED}[ERROR] Le filesystem est encore monte!${NC}"
        echo "Demontez d'abord: umount /mnt/drbd"
        exit 1
    fi

    echo -e "${GREEN}[INFO] Retrogradation en Secondary...${NC}"
    echo "secondary" > "$DRBD_ROLE_FILE"

    echo ""
    echo -e "${GREEN}[SUCCESS] Ce noeud est maintenant SECONDARY${NC}"
}

# Connecter au peer
connect_peer() {
    echo -e "${BLUE}[INFO] Connexion au peer...${NC}"

    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
    fi

    if ping -c 1 -W 2 "$PEER_IP" &>/dev/null; then
        echo "true" > "$DRBD_CONNECTED_FILE"
        echo -e "${GREEN}[SUCCESS] Connecte au peer ($PEER_IP)${NC}"
    else
        echo -e "${RED}[ERROR] Impossible de joindre le peer ($PEER_IP)${NC}"
        exit 1
    fi
}

# Deconnecter du peer
disconnect_peer() {
    echo -e "${BLUE}[INFO] Deconnexion du peer...${NC}"
    echo "false" > "$DRBD_CONNECTED_FILE"
    echo -e "${GREEN}[SUCCESS] Deconnecte${NC}"
}

# Afficher le status
show_status() {
    /scripts/drbd-status.sh
}

# Main
case "${1:-help}" in
    create-md)
        create_metadata
        ;;
    start)
        start_drbd
        ;;
    stop)
        stop_drbd
        ;;
    primary)
        make_primary "$2"
        ;;
    secondary)
        make_secondary
        ;;
    connect)
        connect_peer
        ;;
    disconnect)
        disconnect_peer
        ;;
    status)
        show_status
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
