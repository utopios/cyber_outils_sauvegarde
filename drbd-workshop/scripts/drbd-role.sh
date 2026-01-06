#!/bin/bash
# =============================================================================
# Script de gestion des roles DRBD
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DRBD_ROLE_FILE="/var/lib/drbd/role"
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_SYNC_FILE="/var/lib/drbd/sync"
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"

show_help() {
    cat << EOF

Usage: $0 <role> [options]

Roles:
    primary [--force]   Passer ce noeud en Primary
    secondary           Passer ce noeud en Secondary
    status              Afficher le role actuel

Options:
    --force             Forcer le changement de role meme si non synchronise

Examples:
    $0 primary           # Passer en Primary (si synchronise)
    $0 primary --force   # Forcer en Primary
    $0 secondary         # Passer en Secondary

EOF
}

make_primary() {
    FORCE=false
    if [ "$1" == "--force" ]; then
        FORCE=true
    fi

    CURRENT_ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")
    CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")
    SYNC=$(cat "$DRBD_SYNC_FILE" 2>/dev/null || echo "0")

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Promotion en PRIMARY${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Verifications
    if [ "$CURRENT_ROLE" == "primary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja Primary${NC}"
        return 0
    fi

    # Verifier si le filesystem est monte sur /mnt/drbd (ne devrait pas etre le cas en secondary)
    if mountpoint -q /mnt/drbd 2>/dev/null && [ "$CURRENT_ROLE" == "secondary" ]; then
        echo -e "${RED}[ERROR] Le filesystem est monte mais ce noeud est Secondary!${NC}"
        echo "Etat anormal - verifiez la configuration"
        exit 1
    fi

    if [ "$CONNECTED" == "false" ] && [ "$FORCE" != true ]; then
        echo -e "${RED}[ERROR] Non connecte au peer!${NC}"
        echo ""
        echo "Options:"
        echo "  1. Attendez que le peer soit disponible"
        echo "  2. Utilisez --force (risque de split-brain)"
        echo ""
        exit 1
    fi

    if [ "$SYNC" != "100" ] && [ "$FORCE" != true ]; then
        echo -e "${RED}[ERROR] Synchronisation incomplete (${SYNC}%)${NC}"
        echo ""
        echo "Options:"
        echo "  1. Attendez la fin de la synchronisation"
        echo "  2. Utilisez --force pour forcer"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}[INFO] Verification des preconditions...${NC}"
    echo "  - Role actuel: $CURRENT_ROLE"
    echo "  - Connecte: $CONNECTED"
    echo "  - Sync: $SYNC%"
    echo ""

    if [ "$FORCE" == true ]; then
        echo -e "${YELLOW}[WARN] Mode FORCE active!${NC}"
        echo "  Ceci peut causer un split-brain si le peer est aussi Primary."
        echo ""
    fi

    echo -e "${GREEN}[INFO] Promotion en cours...${NC}"
    sleep 1

    # Effectuer le changement
    echo "primary" > "$DRBD_ROLE_FILE"
    echo "UpToDate" > "$DRBD_STATE_FILE"
    echo "100" > "$DRBD_SYNC_FILE"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SUCCESS: Ce noeud est PRIMARY         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Prochaines etapes:"
    echo "  1. Formatter (si premier usage): mkfs.ext4 /dev/drbd0"
    echo "  2. Monter: mount /dev/drbd0 /mnt/drbd"
    echo "  3. Utiliser: cd /mnt/drbd"
    echo ""
}

make_secondary() {
    CURRENT_ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Retrogradation en SECONDARY${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if [ "$CURRENT_ROLE" == "secondary" ]; then
        echo -e "${YELLOW}[WARN] Ce noeud est deja Secondary${NC}"
        return 0
    fi

    # Verifier si monte
    if mountpoint -q /mnt/drbd 2>/dev/null; then
        echo -e "${RED}[ERROR] Le filesystem est encore monte!${NC}"
        echo ""
        echo "Vous devez d'abord:"
        echo "  1. Arreter les applications utilisant /mnt/drbd"
        echo "  2. Demonter: umount /mnt/drbd"
        echo "  3. Relancer cette commande"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}[INFO] Retrogradation en cours...${NC}"
    sleep 1

    echo "secondary" > "$DRBD_ROLE_FILE"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SUCCESS: Ce noeud est SECONDARY       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Ce noeud est maintenant en standby."
    echo "Les donnees sont repliquees depuis le Primary."
    echo ""
}

show_role() {
    ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")
    echo ""
    echo "Role actuel: $ROLE"
    echo ""
}

# Main
case "${1:-help}" in
    primary)
        make_primary "$2"
        ;;
    secondary)
        make_secondary
        ;;
    status)
        show_role
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
