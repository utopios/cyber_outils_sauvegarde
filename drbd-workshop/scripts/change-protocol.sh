#!/bin/bash
# =============================================================================
# Script de changement de protocole DRBD
# =============================================================================
# Change le protocole de replication DRBD entre A, B et C.
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DRBD_CONF="/etc/drbd.d/r0.res"

show_help() {
    cat << EOF

Usage: $0 <protocol>

Protocols:
    A       Asynchrone (performance maximale)
            - ACK immediat apres ecriture locale
            - Risque de perte de donnees en cas de crash

    B       Semi-synchrone (compromis)
            - ACK apres envoi sur le reseau
            - Donnees peuvent etre en transit

    C       Synchrone (securite maximale)
            - ACK apres ecriture sur le peer
            - Zero perte de donnees

Examples:
    $0 A    # Passer en mode asynchrone
    $0 B    # Passer en mode semi-synchrone
    $0 C    # Passer en mode synchrone

EOF
}

change_protocol() {
    PROTOCOL="$1"

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Changement de protocole DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Valider le protocole
    if [[ ! "$PROTOCOL" =~ ^[ABC]$ ]]; then
        echo -e "${RED}[ERROR] Protocole invalide: $PROTOCOL${NC}"
        echo "Protocoles valides: A, B, C"
        exit 1
    fi

    # Afficher les caracteristiques
    case "$PROTOCOL" in
        A)
            echo -e "Protocole: ${GREEN}A - Asynchrone${NC}"
            echo ""
            echo "Caracteristiques:"
            echo "  - Performance: MAXIMALE"
            echo "  - Securite: FAIBLE"
            echo "  - Latence: MINIMALE"
            echo "  - Usage: Logs, donnees non critiques"
            echo ""
            echo -e "${YELLOW}[WARN] Risque de perte de donnees en cas de crash!${NC}"
            ;;
        B)
            echo -e "Protocole: ${YELLOW}B - Semi-synchrone${NC}"
            echo ""
            echo "Caracteristiques:"
            echo "  - Performance: BONNE"
            echo "  - Securite: MOYENNE"
            echo "  - Latence: MODEREE"
            echo "  - Usage: Donnees importantes, latence reseau faible"
            echo ""
            echo -e "${YELLOW}[WARN] Donnees peuvent etre en transit lors d'un crash${NC}"
            ;;
        C)
            echo -e "Protocole: ${GREEN}C - Synchrone${NC}"
            echo ""
            echo "Caracteristiques:"
            echo "  - Performance: MODEREE"
            echo "  - Securite: MAXIMALE"
            echo "  - Latence: Plus elevee"
            echo "  - Usage: Bases de donnees, donnees critiques"
            echo ""
            echo -e "${GREEN}[INFO] Zero perte de donnees garantie${NC}"
            ;;
    esac

    echo ""
    read -p "Confirmer le changement? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation annulee."
        exit 0
    fi

    echo ""
    echo -e "${GREEN}[INFO] Modification de la configuration...${NC}"

    # Modifier le fichier de configuration
    if [ -f "$DRBD_CONF" ]; then
        sed -i "s/protocol [ABC];/protocol $PROTOCOL;/" "$DRBD_CONF"
        echo "  Configuration mise a jour: $DRBD_CONF"
    else
        echo -e "${YELLOW}[WARN] Fichier de configuration non trouve${NC}"
        echo "  Creation d'une configuration simulee..."
    fi

    echo ""
    echo -e "${GREEN}[INFO] Application des changements...${NC}"
    # En production: drbdadm adjust r0
    sleep 1
    echo "  Changements appliques (simulation)"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Protocol change en: $PROTOCOL                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Pour verifier: /scripts/drbd-status.sh"
    echo "Pour benchmarker: /scripts/benchmark.sh write"
    echo ""
}

# Main
case "${1:-help}" in
    A|B|C)
        change_protocol "$1"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Protocole invalide: $1${NC}"
        show_help
        exit 1
        ;;
esac
