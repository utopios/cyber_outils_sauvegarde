#!/bin/bash
# =============================================================================
# Script de Failover DRBD
# =============================================================================
# Ce script effectue un failover complet du cluster DRBD.
# Il peut etre utilise pour un failover planifie ou d'urgence.
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
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_SYNC_FILE="/var/lib/drbd/sync"
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"
MOUNT_POINT="/mnt/drbd"

show_help() {
    cat << EOF

Usage: $0 <command> [options]

Commands:
    planned             Failover planifie (graceful)
    emergency           Failover d'urgence (force)
    takeover            Prendre le role Primary
    release             Liberer le role Primary
    status              Voir le status du cluster

Options:
    --no-prompt         Ne pas demander de confirmation
    --notify            Envoyer une notification (simule)

Examples:
    $0 planned          # Failover propre avec confirmation
    $0 emergency        # Failover force en cas de panne
    $0 takeover         # Devenir Primary

EOF
}

check_role() {
    cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown"
}

check_mounted() {
    mountpoint -q "$MOUNT_POINT" 2>/dev/null
    return $?
}

planned_failover() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           DRBD PLANNED FAILOVER                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    CURRENT_ROLE=$(check_role)
    echo -e "Role actuel: ${YELLOW}${CURRENT_ROLE^^}${NC}"
    echo ""

    if [ "$CURRENT_ROLE" != "primary" ]; then
        echo -e "${RED}[ERROR] Ce noeud n'est pas Primary!${NC}"
        echo "Un failover planifie doit etre initie depuis le Primary."
        echo ""
        echo "Options:"
        echo "  - Utilisez 'takeover' pour devenir Primary"
        echo "  - Ou connectez-vous au noeud Primary actuel"
        exit 1
    fi

    if [ "$1" != "--no-prompt" ]; then
        echo -e "${YELLOW}[ATTENTION] Cette operation va:${NC}"
        echo "  1. Arreter les applications sur ce noeud"
        echo "  2. Demonter le filesystem DRBD"
        echo "  3. Passer ce noeud en Secondary"
        echo "  4. Le peer deviendra automatiquement Primary"
        echo ""
        read -p "Continuer? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation annulee."
            exit 0
        fi
    fi

    echo ""
    echo -e "${GREEN}[1/4] Verification des applications...${NC}"
    # Dans un cas reel, on arreterait PostgreSQL, etc.
    sleep 1
    echo "      Aucune application a arreter (simulation)"

    echo ""
    echo -e "${GREEN}[2/4] Demontage du filesystem...${NC}"
    if check_mounted; then
        umount "$MOUNT_POINT" 2>/dev/null || true
        echo "      Filesystem demonte"
    else
        echo "      Filesystem non monte"
    fi

    echo ""
    echo -e "${GREEN}[3/4] Passage en Secondary...${NC}"
    echo "secondary" > "$DRBD_ROLE_FILE"
    sleep 1
    echo "      Role change en Secondary"

    echo ""
    echo -e "${GREEN}[4/4] Notification au peer...${NC}"
    # Simulation - en reel, on utiliserait un mecanisme de cluster
    sleep 1
    echo "      Peer notifie (simulation)"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           FAILOVER COMPLETE                               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Ce noeud est maintenant SECONDARY."
    echo "Le peer doit maintenant prendre le role PRIMARY."
    echo ""
    echo "Sur le peer, executez:"
    echo "  /scripts/failover.sh takeover"
    echo ""
}

emergency_failover() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           DRBD EMERGENCY FAILOVER                         ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    CURRENT_ROLE=$(check_role)
    echo -e "Role actuel: ${YELLOW}${CURRENT_ROLE^^}${NC}"
    echo ""

    if [ "$CURRENT_ROLE" == "primary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja Primary${NC}"
        return 0
    fi

    if [ "$1" != "--no-prompt" ]; then
        echo -e "${RED}[ATTENTION] FAILOVER D'URGENCE${NC}"
        echo ""
        echo "Cette operation va forcer ce noeud a devenir Primary"
        echo "MEME SI l'autre noeud est injoignable."
        echo ""
        echo -e "${RED}RISQUE DE SPLIT-BRAIN si l'autre noeud est encore actif!${NC}"
        echo ""
        read -p "Etes-vous SUR de vouloir continuer? (yes/no) " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Operation annulee."
            exit 0
        fi
    fi

    echo ""
    echo -e "${YELLOW}[1/3] Deconnexion du peer (force)...${NC}"
    echo "false" > "$DRBD_CONNECTED_FILE"
    sleep 1
    echo "      Deconnecte"

    echo ""
    echo -e "${YELLOW}[2/3] Promotion en Primary (force)...${NC}"
    echo "primary" > "$DRBD_ROLE_FILE"
    echo "UpToDate" > "$DRBD_STATE_FILE"
    echo "100" > "$DRBD_SYNC_FILE"
    sleep 1
    echo "      Promu en Primary"

    echo ""
    echo -e "${YELLOW}[3/3] Montage du filesystem...${NC}"
    mkdir -p "$MOUNT_POINT"
    # Simulation de montage
    echo "      Filesystem pret a etre monte"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           EMERGENCY FAILOVER COMPLETE                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC}"
    echo "  1. Verifiez que l'ancien Primary est bien arrete"
    echo "  2. Quand il sera de retour, il devra se resynchroniser"
    echo "  3. Surveillez les logs pour tout signe de split-brain"
    echo ""
}

takeover() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Prise de role Primary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    CURRENT_ROLE=$(check_role)
    CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")

    if [ "$CURRENT_ROLE" == "primary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja Primary${NC}"
        return 0
    fi

    if [ "$CONNECTED" == "false" ]; then
        echo -e "${YELLOW}[WARN] Non connecte au peer${NC}"
        echo "Utilisez 'emergency' pour un failover force"
        exit 1
    fi

    echo -e "${GREEN}[INFO] Promotion en Primary...${NC}"
    echo "primary" > "$DRBD_ROLE_FILE"
    echo "UpToDate" > "$DRBD_STATE_FILE"

    echo ""
    echo -e "${GREEN}[SUCCESS] Ce noeud est maintenant PRIMARY${NC}"
    echo ""
    echo "Vous pouvez maintenant monter le filesystem:"
    echo "  mount /dev/drbd0 /mnt/drbd"
    echo ""
}

release_role() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Liberation du role Primary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    CURRENT_ROLE=$(check_role)

    if [ "$CURRENT_ROLE" != "primary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud n'est pas Primary${NC}"
        return 0
    fi

    if check_mounted; then
        echo -e "${RED}[ERROR] Le filesystem est encore monte!${NC}"
        echo "Demontez d'abord: umount /mnt/drbd"
        exit 1
    fi

    echo -e "${GREEN}[INFO] Passage en Secondary...${NC}"
    echo "secondary" > "$DRBD_ROLE_FILE"

    echo ""
    echo -e "${GREEN}[SUCCESS] Ce noeud est maintenant SECONDARY${NC}"
}

show_status() {
    /scripts/drbd-status.sh
}

# Main
case "${1:-help}" in
    planned)
        planned_failover "$2"
        ;;
    emergency)
        emergency_failover "$2"
        ;;
    takeover)
        takeover
        ;;
    release)
        release_role
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
