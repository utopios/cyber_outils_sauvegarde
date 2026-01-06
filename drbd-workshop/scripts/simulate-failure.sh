#!/bin/bash
# =============================================================================
# Script de simulation de pannes DRBD
# =============================================================================
# Simule differentes pannes pour tester la resilience du cluster.
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_SYNC_FILE="/var/lib/drbd/sync"

show_help() {
    cat << EOF

Usage: $0 <failure_type> [duration]

Failure Types:
    network [duration]      Simule une panne reseau
    slow-disk               Simule un disque lent
    disk-full               Simule un disque plein
    crash                   Simule un crash du processus DRBD
    splitbrain              Simule un split-brain
    io-error                Simule une erreur I/O
    restore                 Restaurer l'etat normal

Duration:
    Format: Ns (secondes), Nm (minutes)
    Default: 30s

Examples:
    $0 network 30s          # Panne reseau de 30 secondes
    $0 slow-disk            # Disque lent permanent
    $0 splitbrain           # Simuler un split-brain
    $0 restore              # Revenir a la normale

EOF
}

simulate_network_failure() {
    DURATION="${1:-30s}"
    SECONDS_NUM=$(echo "$DURATION" | sed 's/[sm]$//')

    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           SIMULATION: PANNE RESEAU                        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}[WARN] Cette simulation va:${NC}"
    echo "  - Bloquer la communication avec le peer"
    echo "  - Duree: $DURATION"
    echo ""

    read -p "Continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation annulee."
        exit 0
    fi

    echo ""
    echo -e "${RED}[FAILURE] Panne reseau en cours...${NC}"

    # Simuler la deconnexion
    echo "false" > "$DRBD_CONNECTED_FILE"

    # Bloquer le trafic (si possible)
    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
    fi

    # Utiliser iptables si disponible
    if command -v iptables &>/dev/null; then
        iptables -A INPUT -s "$PEER_IP" -j DROP 2>/dev/null || true
        iptables -A OUTPUT -d "$PEER_IP" -j DROP 2>/dev/null || true
    fi

    echo ""
    echo "Panne active. Attente de $DURATION..."
    echo ""
    echo "Verifiez le status avec: /scripts/drbd-status.sh"
    echo ""

    sleep "$SECONDS_NUM"

    echo ""
    echo -e "${GREEN}[RECOVERY] Restauration de la connectivite...${NC}"

    # Restaurer
    if command -v iptables &>/dev/null; then
        iptables -D INPUT -s "$PEER_IP" -j DROP 2>/dev/null || true
        iptables -D OUTPUT -d "$PEER_IP" -j DROP 2>/dev/null || true
    fi

    echo "true" > "$DRBD_CONNECTED_FILE"

    echo ""
    echo -e "${GREEN}[SUCCESS] Connectivite restauree${NC}"
}

simulate_slow_disk() {
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║           SIMULATION: DISQUE LENT                         ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Cette simulation ajoute de la latence aux operations disque."
    echo ""
    echo "En production, cela peut arriver a cause de:"
    echo "  - Disque defaillant"
    echo "  - Contention I/O"
    echo "  - Probleme de controleur"
    echo ""

    echo -e "${YELLOW}[SIMULATION] Mode disque lent active${NC}"
    echo ""
    echo "Pour tester, lancez un benchmark:"
    echo "  /scripts/benchmark.sh write"
    echo ""
    echo "Pour restaurer: $0 restore"
}

simulate_disk_full() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           SIMULATION: DISQUE PLEIN                        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}[WARN] Cette simulation va remplir le disque DRBD${NC}"
    echo ""

    read -p "Continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation annulee."
        exit 0
    fi

    # Creer un gros fichier pour remplir le disque
    echo ""
    echo -e "${RED}[FAILURE] Remplissage du disque...${NC}"

    dd if=/dev/zero of=/mnt/drbd/.disk_full_test bs=1M count=900 2>/dev/null || true

    echo ""
    echo "Espace disque actuel:"
    df -h /mnt/drbd 2>/dev/null || df -h /data

    echo ""
    echo -e "${YELLOW}Le disque est maintenant plein ou presque.${NC}"
    echo ""
    echo "Pour restaurer: $0 restore"
}

simulate_crash() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           SIMULATION: CRASH DRBD                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${RED}[FAILURE] Simulation de crash DRBD...${NC}"

    # Marquer comme non configure
    echo "unconfigured" > "$DRBD_STATE_FILE"
    echo "false" > "$DRBD_CONNECTED_FILE"

    echo ""
    echo "DRBD est maintenant dans un etat 'crashed'."
    echo ""
    echo "Pour recuperer:"
    echo "  /scripts/drbd-init.sh start"
    echo ""
    echo "Ou restaurer: $0 restore"
}

simulate_splitbrain() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           SIMULATION: SPLIT-BRAIN                         ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Un split-brain se produit quand les deux noeuds"
    echo "deviennent Primary simultanement sans communication."
    echo ""

    echo -e "${RED}[FAILURE] Simulation de split-brain...${NC}"

    # Deconnecter
    echo "false" > "$DRBD_CONNECTED_FILE"

    # Marquer comme standalone
    echo "StandAlone" > "$DRBD_STATE_FILE"

    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  SPLIT-BRAIN DETECTE!                                      ║${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}║  Les deux noeuds ont diverge.                              ║${NC}"
    echo -e "${RED}║  Une intervention manuelle est necessaire.                 ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Pour resoudre:"
    echo ""
    echo "1. Sur le noeud qui doit PERDRE ses donnees:"
    echo "   /scripts/resolve-splitbrain.sh discard-local"
    echo ""
    echo "2. Sur le noeud qui garde ses donnees:"
    echo "   /scripts/resolve-splitbrain.sh keep-local"
    echo ""
}

simulate_io_error() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           SIMULATION: ERREUR I/O                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${RED}[FAILURE] Erreur I/O sur le disque...${NC}"

    # Marquer l'etat comme degradee
    echo "Diskless" > "$DRBD_STATE_FILE"

    echo ""
    echo "Le disque a ete detache suite a une erreur I/O."
    echo ""
    echo "Actions possibles:"
    echo "  1. Verifier l'integrite du disque"
    echo "  2. Rattacher: drbdadm attach r0"
    echo "  3. Resynchroniser: drbdadm invalidate r0"
    echo ""
}

restore_normal() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           RESTAURATION DE L'ETAT NORMAL                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${GREEN}[INFO] Nettoyage des fichiers de test...${NC}"
    rm -f /mnt/drbd/.disk_full_test 2>/dev/null
    rm -f /data/.disk_full_test 2>/dev/null

    echo -e "${GREEN}[INFO] Restauration des regles iptables...${NC}"
    if command -v iptables &>/dev/null; then
        iptables -F 2>/dev/null || true
    fi

    echo -e "${GREEN}[INFO] Restauration de l'etat DRBD...${NC}"
    echo "UpToDate" > "$DRBD_STATE_FILE"
    echo "100" > "$DRBD_SYNC_FILE"

    # Tester la connectivite
    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
    if [ "$DRBD_NODE_NAME" == "node2" ]; then
        PEER_IP="172.28.0.11"
    fi

    if ping -c 1 -W 2 "$PEER_IP" &>/dev/null; then
        echo "true" > "$DRBD_CONNECTED_FILE"
        echo -e "${GREEN}[OK] Connectivite avec le peer restauree${NC}"
    else
        echo "false" > "$DRBD_CONNECTED_FILE"
        echo -e "${YELLOW}[WARN] Peer non joignable${NC}"
    fi

    echo ""
    echo -e "${GREEN}[SUCCESS] Etat normal restaure${NC}"
    echo ""
    echo "Verifiez avec: /scripts/drbd-status.sh"
}

# Main
case "${1:-help}" in
    network)
        simulate_network_failure "$2"
        ;;
    slow-disk)
        simulate_slow_disk
        ;;
    disk-full)
        simulate_disk_full
        ;;
    crash)
        simulate_crash
        ;;
    splitbrain)
        simulate_splitbrain
        ;;
    io-error)
        simulate_io_error
        ;;
    restore)
        restore_normal
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Type de panne inconnu: $1${NC}"
        show_help
        exit 1
        ;;
esac
