#!/bin/bash
# =============================================================================
# Script de monitoring DRBD en temps reel
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_ROLE_FILE="/var/lib/drbd/role"
DRBD_SYNC_FILE="/var/lib/drbd/sync"
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"

show_help() {
    cat << EOF

Usage: $0 <command>

Commands:
    watch       Monitoring continu (rafraichissement toutes les 2s)
    once        Afficher une fois et quitter
    latency     Mesurer la latence avec le peer
    network     Statistiques reseau
    disk        Statistiques disque
    all         Toutes les metriques

Examples:
    $0 watch    # Mode surveillance continue
    $0 latency  # Mesurer la latence

EOF
}

draw_dashboard() {
    clear

    # Lire les etats
    STATE=$(cat "$DRBD_STATE_FILE" 2>/dev/null || echo "Unknown")
    ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "Unknown")
    SYNC=$(cat "$DRBD_SYNC_FILE" 2>/dev/null || echo "0")
    CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")

    # Date et heure
    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    # Determiner les IPs
    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    NODE_IP="${DRBD_NODE_IP:-172.28.0.11}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
        NODE_IP="172.28.0.12"
    fi

    # Tester la connectivite
    LATENCY="N/A"
    if ping -c 1 -W 1 "$PEER_IP" &>/dev/null; then
        LATENCY=$(ping -c 1 -W 1 "$PEER_IP" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1 ms/')
    fi

    # Barre de progression sync
    PROGRESS_BAR=""
    PROGRESS_FILLED=$((SYNC / 5))
    for ((i=0; i<20; i++)); do
        if [ $i -lt $PROGRESS_FILLED ]; then
            PROGRESS_BAR+="█"
        else
            PROGRESS_BAR+="░"
        fi
    done

    # Statistiques systeme
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' 2>/dev/null || echo "N/A")
    MEM_USAGE=$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}' 2>/dev/null || echo "N/A")
    DISK_USAGE=$(df -h /data 2>/dev/null | awk 'NR==2{print $5}' || echo "N/A")

    # Affichage
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                     DRBD MONITOR - Real-Time Dashboard                    ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Time: ${NOW}                                              ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${WHITE}CLUSTER STATUS${NC}                                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ──────────────                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"

    # Afficher les deux noeuds cote a cote
    if [ "$DRBD_NODE_NAME" == "node1" ]; then
        # Node 1 local
        if [ "$ROLE" == "primary" ]; then
            echo -e "${CYAN}║${NC}   ┌─────────────────────┐      ┌─────────────────────┐              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${GREEN}NODE 1 (LOCAL)${NC}     │      │  ${BLUE}NODE 2 (PEER)${NC}       │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${GREEN}█ PRIMARY${NC}          │◄────►│  ${BLUE}□ SECONDARY${NC}        │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${NODE_IP}      │      │  ${PEER_IP}      │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   └─────────────────────┘      └─────────────────────┘              ${CYAN}║${NC}"
        else
            echo -e "${CYAN}║${NC}   ┌─────────────────────┐      ┌─────────────────────┐              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${BLUE}NODE 1 (LOCAL)${NC}     │      │  ${GREEN}NODE 2 (PEER)${NC}       │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${BLUE}□ SECONDARY${NC}        │◄────►│  ${GREEN}█ PRIMARY${NC}          │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${NODE_IP}      │      │  ${PEER_IP}      │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   └─────────────────────┘      └─────────────────────┘              ${CYAN}║${NC}"
        fi
    else
        # Node 2 local
        if [ "$ROLE" == "primary" ]; then
            echo -e "${CYAN}║${NC}   ┌─────────────────────┐      ┌─────────────────────┐              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${BLUE}NODE 1 (PEER)${NC}      │      │  ${GREEN}NODE 2 (LOCAL)${NC}      │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${BLUE}□ SECONDARY${NC}        │◄────►│  ${GREEN}█ PRIMARY${NC}          │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${PEER_IP}      │      │  ${NODE_IP}      │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   └─────────────────────┘      └─────────────────────┘              ${CYAN}║${NC}"
        else
            echo -e "${CYAN}║${NC}   ┌─────────────────────┐      ┌─────────────────────┐              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${GREEN}NODE 1 (PEER)${NC}      │      │  ${BLUE}NODE 2 (LOCAL)${NC}      │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${GREEN}█ PRIMARY${NC}          │◄────►│  ${BLUE}□ SECONDARY${NC}        │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   │  ${PEER_IP}      │      │  ${NODE_IP}      │              ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   └─────────────────────┘      └─────────────────────┘              ${CYAN}║${NC}"
        fi
    fi

    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${WHITE}REPLICATION${NC}                                                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ───────────                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"

    # Status de connexion
    if [ "$CONNECTED" == "true" ]; then
        echo -e "${CYAN}║${NC}   Connection: ${GREEN}●${NC} Connected                                              ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}   Connection: ${RED}●${NC} Disconnected                                           ${CYAN}║${NC}"
    fi

    echo -e "${CYAN}║${NC}   Protocol: C (Synchronous)                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Latency: ${LATENCY}                                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Sync Progress: [${GREEN}${PROGRESS_BAR}${NC}] ${SYNC}%                        ${CYAN}║${NC}"

    if [ "$SYNC" == "100" ]; then
        echo -e "${CYAN}║${NC}   Status: ${GREEN}Fully Synchronized${NC}                                           ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}   Status: ${YELLOW}Synchronizing...${NC}                                             ${CYAN}║${NC}"
    fi

    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${WHITE}SYSTEM RESOURCES${NC}                                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ────────────────                                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   CPU: ${CPU_USAGE}%    Memory: ${MEM_USAGE}    Disk: ${DISK_USAGE}                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Press ${WHITE}Ctrl+C${NC} to exit                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
}

watch_mode() {
    echo "Demarrage du monitoring... (Ctrl+C pour quitter)"
    while true; do
        draw_dashboard
        sleep 2
    done
}

measure_latency() {
    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
    fi

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Mesure de latence vers le peer${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Peer: $PEER_IP"
    echo ""

    ping -c 10 "$PEER_IP"

    echo ""
    echo -e "${GREEN}Mesure terminee${NC}"
}

network_stats() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Statistiques Reseau${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo "Interfaces reseau:"
    ip -s link show

    echo ""
    echo "Connexions actives:"
    netstat -an | grep -E "7788|ESTABLISHED" | head -20
}

disk_stats() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Statistiques Disque${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo "Utilisation des disques:"
    df -h

    echo ""
    echo "Fichier DRBD:"
    ls -lh /data/drbd-disk.img 2>/dev/null || echo "Non trouve"

    echo ""
    echo "Point de montage:"
    if mountpoint -q /mnt/drbd 2>/dev/null; then
        df -h /mnt/drbd
        echo ""
        echo "Contenu:"
        ls -la /mnt/drbd
    else
        echo "Non monte"
    fi
}

all_metrics() {
    /scripts/drbd-status.sh
    network_stats
    disk_stats
}

# Main
case "${1:-help}" in
    watch)
        watch_mode
        ;;
    once)
        draw_dashboard
        ;;
    latency)
        measure_latency
        ;;
    network)
        network_stats
        ;;
    disk)
        disk_stats
        ;;
    all)
        all_metrics
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
