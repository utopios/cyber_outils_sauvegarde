#!/bin/bash
# =============================================================================
# Script de resolution de Split-Brain DRBD
# =============================================================================
# Resout un split-brain en choisissant quel noeud garde ses donnees.
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_ROLE_FILE="/var/lib/drbd/role"
DRBD_SYNC_FILE="/var/lib/drbd/sync"
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"

show_help() {
    cat << EOF

Usage: $0 <action>

Actions:
    discard-local       Abandonner les donnees locales et resync depuis peer
    keep-local          Garder les donnees locales (le peer devra resync)
    status              Voir l'etat du split-brain

Procedure de resolution:

    1. Identifiez quel noeud a les donnees les plus recentes/correctes

    2. Sur le noeud qui doit PERDRE ses donnees:
       $0 discard-local

    3. Sur le noeud qui GARDE ses donnees:
       $0 keep-local

WARNING:
    Cette operation est IRREVERSIBLE!
    Les donnees du noeud "discard" seront PERDUES.

EOF
}

check_splitbrain() {
    STATE=$(cat "$DRBD_STATE_FILE" 2>/dev/null || echo "Unknown")
    CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")

    if [ "$STATE" == "StandAlone" ] || [ "$CONNECTED" == "false" ]; then
        return 0  # Split-brain possible
    fi
    return 1  # Pas de split-brain
}

show_splitbrain_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           STATUS SPLIT-BRAIN                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    STATE=$(cat "$DRBD_STATE_FILE" 2>/dev/null || echo "Unknown")
    ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "Unknown")
    CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")

    echo "Etat actuel de ce noeud:"
    echo "  - State: $STATE"
    echo "  - Role: $ROLE"
    echo "  - Connected: $CONNECTED"
    echo ""

    if check_splitbrain; then
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  SPLIT-BRAIN DETECTE OU POSSIBLE                           ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Le cluster est dans un etat anormal."
        echo ""
        echo "Actions recommandees:"
        echo "  1. Verifiez l'etat de l'autre noeud"
        echo "  2. Determinez quel noeud a les bonnes donnees"
        echo "  3. Sur le noeud a JETER: $0 discard-local"
        echo "  4. Sur le noeud a GARDER: $0 keep-local"
    else
        echo -e "${GREEN}[OK] Pas de split-brain detecte${NC}"
    fi
}

discard_local_data() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ABANDON DES DONNEES LOCALES                     ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${RED}[WARNING] Cette operation va:${NC}"
    echo "  - SUPPRIMER les donnees locales"
    echo "  - Resynchroniser depuis le peer"
    echo "  - Cette action est IRREVERSIBLE"
    echo ""

    read -p "Etes-vous SUR? Tapez 'DISCARD' pour confirmer: " CONFIRM
    if [ "$CONFIRM" != "DISCARD" ]; then
        echo "Operation annulee."
        exit 0
    fi

    echo ""
    echo -e "${YELLOW}[1/4] Deconnexion du cluster...${NC}"
    echo "false" > "$DRBD_CONNECTED_FILE"
    sleep 1

    echo -e "${YELLOW}[2/4] Passage en Secondary...${NC}"
    echo "secondary" > "$DRBD_ROLE_FILE"
    sleep 1

    echo -e "${YELLOW}[3/4] Marquage des donnees comme obsoletes...${NC}"
    echo "Outdated" > "$DRBD_STATE_FILE"
    echo "0" > "$DRBD_SYNC_FILE"
    sleep 1

    echo -e "${YELLOW}[4/4] Preparation pour resynchronisation...${NC}"
    # En production: drbdadm -- --discard-my-data connect r0
    sleep 1

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  PRET POUR RESYNCHRONISATION                               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Ce noeud est pret a recevoir les donnees du peer."
    echo ""
    echo "Maintenant, sur l'AUTRE noeud, executez:"
    echo "  /scripts/resolve-splitbrain.sh keep-local"
    echo ""
}

keep_local_data() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           CONSERVATION DES DONNEES LOCALES                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Ce noeud va garder ses donnees et les propager au peer."
    echo ""

    read -p "Confirmer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation annulee."
        exit 0
    fi

    echo ""
    echo -e "${GREEN}[1/4] Configuration en Primary...${NC}"
    echo "primary" > "$DRBD_ROLE_FILE"
    sleep 1

    echo -e "${GREEN}[2/4] Marquage des donnees comme valides...${NC}"
    echo "UpToDate" > "$DRBD_STATE_FILE"
    echo "100" > "$DRBD_SYNC_FILE"
    sleep 1

    echo -e "${GREEN}[3/4] Tentative de connexion au peer...${NC}"

    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
    fi

    if ping -c 1 -W 2 "$PEER_IP" &>/dev/null; then
        echo "true" > "$DRBD_CONNECTED_FILE"
        echo "  Peer joignable"
    else
        echo "false" > "$DRBD_CONNECTED_FILE"
        echo "  Peer non joignable - attente..."
    fi

    sleep 1

    echo -e "${GREEN}[4/4] Demarrage de la synchronisation...${NC}"
    # En production: drbdadm connect r0
    sleep 1

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SPLIT-BRAIN RESOLU                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Ce noeud est PRIMARY avec les donnees valides."
    echo ""
    echo "Le peer va se resynchroniser automatiquement."
    echo ""
    echo "Verifiez le status: /scripts/drbd-status.sh"
}

# Main
case "${1:-help}" in
    discard-local|discard)
        discard_local_data
        ;;
    keep-local|keep)
        keep_local_data
        ;;
    status)
        show_splitbrain_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Action inconnue: $1${NC}"
        show_help
        exit 1
        ;;
esac
