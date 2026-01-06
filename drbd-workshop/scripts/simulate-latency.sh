#!/bin/bash
# =============================================================================
# Script de simulation de latence reseau DRBD
# =============================================================================
# Ce script ajoute de la latence artificielle au reseau pour observer
# l'impact sur les differents protocoles DRBD (A, B, C).
# Utilise tc (traffic control) pour manipuler le trafic reseau.
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
INTERFACE="${DRBD_INTERFACE:-eth0}"
PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"

# Detecter le peer selon le noeud
if [ "$DRBD_NODE_NAME" == "node2" ]; then
    PEER_IP="172.28.0.11"
fi

show_help() {
    cat << EOF

Usage: $0 <latency> [options]

Latency Formats:
    Xms             Latence en millisecondes (ex: 50ms, 100ms)
    Xs              Latence en secondes (ex: 1s)

Options:
    --jitter=Xms    Ajouter de la variation (jitter)
    --loss=X%       Ajouter un pourcentage de perte de paquets
    --interface=IF  Interface reseau (default: eth0)
    reset           Supprimer toute latence artificielle

Examples:
    $0 50ms                     # Ajouter 50ms de latence
    $0 100ms --jitter=10ms      # 100ms +/- 10ms de variation
    $0 200ms --loss=1%          # 200ms avec 1% de perte
    $0 reset                    # Supprimer la latence

Cas d'usage typiques:
    - WAN simulation:           $0 50ms
    - Inter-datacenter:         $0 100ms --jitter=20ms
    - Liaison satellite:        $0 600ms --jitter=50ms
    - Reseau degrade:           $0 200ms --loss=5%

EOF
}

check_tc() {
    if ! command -v tc &>/dev/null; then
        echo -e "${YELLOW}[WARN] tc (traffic control) non disponible${NC}"
        echo ""
        echo "Installation: apt-get install iproute2"
        echo ""
        echo "Mode simulation active - les valeurs seront affichees mais pas appliquees."
        return 1
    fi
    return 0
}

show_current_latency() {
    echo ""
    echo -e "${CYAN}Configuration actuelle:${NC}"
    echo ""

    if check_tc; then
        tc qdisc show dev "$INTERFACE" 2>/dev/null | grep -q "netem" && {
            echo "Latence active sur $INTERFACE:"
            tc qdisc show dev "$INTERFACE" 2>/dev/null | grep netem
        } || {
            echo "Aucune latence artificielle configuree"
        }
    else
        echo "(Mode simulation - tc non disponible)"
    fi
    echo ""
}

add_latency() {
    LATENCY="$1"
    JITTER="${2:-0ms}"
    LOSS="${3:-0%}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           SIMULATION DE LATENCE RESEAU                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Configuration:"
    echo "  - Interface: $INTERFACE"
    echo "  - Peer: $PEER_IP"
    echo "  - Latence: $LATENCY"
    if [ "$JITTER" != "0ms" ]; then
        echo "  - Jitter: +/- $JITTER"
    fi
    if [ "$LOSS" != "0%" ]; then
        echo "  - Perte paquets: $LOSS"
    fi
    echo ""

    # Extraire la valeur numerique pour les calculs
    LATENCY_MS=$(echo "$LATENCY" | sed 's/ms$//' | sed 's/s$/000/')

    echo -e "${YELLOW}Impact attendu sur les protocoles DRBD:${NC}"
    echo ""
    echo "┌────────────┬─────────────────────────────────────────────────┐"
    echo "│ Protocol   │ Impact avec ${LATENCY} de latence                      │"
    echo "├────────────┼─────────────────────────────────────────────────┤"

    if [ "$LATENCY_MS" -lt 10 ]; then
        echo "│ A (async)  │ Impact minimal - ecritures non bloquees        │"
        echo "│ B (semi)   │ Impact faible - attente ACK memoire            │"
        echo "│ C (sync)   │ Impact modere - attente ACK disque             │"
    elif [ "$LATENCY_MS" -lt 50 ]; then
        echo "│ A (async)  │ Impact faible - buffer absorbe la latence      │"
        echo "│ B (semi)   │ Impact modere - ralentissement notable         │"
        echo "│ C (sync)   │ Impact significatif - chaque write attend      │"
    elif [ "$LATENCY_MS" -lt 200 ]; then
        echo "│ A (async)  │ Impact modere - risque de buffer plein         │"
        echo "│ B (semi)   │ Impact eleve - performances degradees          │"
        echo "│ C (sync)   │ Impact severe - latence domine les perfs       │"
    else
        echo "│ A (async)  │ Impact eleve - buffer sature rapidement        │"
        echo "│ B (semi)   │ Impact severe - quasi inutilisable             │"
        echo "│ C (sync)   │ Impact critique - latence = temps write        │"
    fi

    echo "└────────────┴─────────────────────────────────────────────────┘"
    echo ""

    if check_tc; then
        echo -e "${GREEN}[INFO] Application de la latence...${NC}"

        # Supprimer l'ancienne configuration
        tc qdisc del dev "$INTERFACE" root 2>/dev/null || true

        # Construire la commande tc
        TC_CMD="tc qdisc add dev $INTERFACE root netem delay $LATENCY"

        if [ "$JITTER" != "0ms" ]; then
            TC_CMD="$TC_CMD $JITTER distribution normal"
        fi

        if [ "$LOSS" != "0%" ]; then
            TC_CMD="$TC_CMD loss $LOSS"
        fi

        # Appliquer
        if $TC_CMD 2>/dev/null; then
            echo -e "${GREEN}[OK] Latence appliquee avec succes${NC}"
        else
            echo -e "${YELLOW}[WARN] Impossible d'appliquer (privileges root requis?)${NC}"
            echo "Commande: $TC_CMD"
        fi
    else
        echo -e "${YELLOW}[SIMULATION] Latence NON appliquee (tc non disponible)${NC}"
    fi

    echo ""
    echo -e "${CYAN}Pour tester l'impact:${NC}"
    echo "  1. Verifier la latence: ping $PEER_IP"
    echo "  2. Lancer un benchmark: /scripts/benchmark.sh write"
    echo "  3. Observer les protocoles: /scripts/change-protocol.sh <A|B|C>"
    echo ""
    echo "Pour supprimer la latence: $0 reset"
    echo ""
}

reset_latency() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           SUPPRESSION DE LA LATENCE                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if check_tc; then
        if tc qdisc del dev "$INTERFACE" root 2>/dev/null; then
            echo -e "${GREEN}[OK] Latence supprimee${NC}"
        else
            echo -e "${YELLOW}[INFO] Aucune latence a supprimer ou privileges insuffisants${NC}"
        fi
    else
        echo -e "${YELLOW}[SIMULATION] Reset simule${NC}"
    fi

    echo ""
    echo "Verification de la connectivite:"
    if ping -c 2 -W 2 "$PEER_IP" &>/dev/null; then
        PING_TIME=$(ping -c 1 "$PEER_IP" 2>/dev/null | grep "time=" | sed 's/.*time=//' | sed 's/ .*//')
        echo -e "${GREEN}[OK] Peer joignable - latence: $PING_TIME${NC}"
    else
        echo -e "${YELLOW}[WARN] Peer non joignable${NC}"
    fi
    echo ""
}

measure_current_latency() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           MESURE DE LATENCE ACTUELLE                      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Ping vers le peer ($PEER_IP):"
    echo ""

    if ping -c 5 "$PEER_IP" 2>/dev/null; then
        echo ""
    else
        echo -e "${RED}[ERROR] Peer non joignable${NC}"
    fi
}

# Parse arguments
JITTER="0ms"
LOSS="0%"

for arg in "$@"; do
    case $arg in
        --jitter=*)
            JITTER="${arg#*=}"
            ;;
        --loss=*)
            LOSS="${arg#*=}"
            ;;
        --interface=*)
            INTERFACE="${arg#*=}"
            ;;
    esac
done

# Main
case "${1:-help}" in
    reset|clear|remove)
        reset_latency
        ;;
    status|show)
        show_current_latency
        ;;
    measure|ping)
        measure_current_latency
        ;;
    help|--help|-h)
        show_help
        ;;
    *ms|*s)
        add_latency "$1" "$JITTER" "$LOSS"
        ;;
    *)
        echo -e "${RED}Format de latence invalide: $1${NC}"
        echo "Utilisez un format comme: 50ms, 100ms, 1s"
        echo ""
        show_help
        exit 1
        ;;
esac
