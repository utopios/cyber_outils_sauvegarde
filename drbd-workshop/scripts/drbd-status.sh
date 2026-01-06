#!/bin/bash
# =============================================================================
# Script de status DRBD (Simulation)
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DRBD_STATE_FILE="/var/lib/drbd/state"
DRBD_ROLE_FILE="/var/lib/drbd/role"
DRBD_SYNC_FILE="/var/lib/drbd/sync"
DRBD_CONNECTED_FILE="/var/lib/drbd/connected"

# Lire l'etat
STATE=$(cat "$DRBD_STATE_FILE" 2>/dev/null || echo "Unknown")
ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "Unknown")
SYNC=$(cat "$DRBD_SYNC_FILE" 2>/dev/null || echo "0")
CONNECTED=$(cat "$DRBD_CONNECTED_FILE" 2>/dev/null || echo "false")

# Determiner le peer
PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"
NODE_IP="${DRBD_NODE_IP:-172.28.0.11}"
if [ "$DRBD_NODE_NAME" == "node2" ]; then
    PEER_IP="172.28.0.11"
    NODE_IP="172.28.0.12"
fi

# Verifier la connectivite reelle
PEER_REACHABLE="No"
if ping -c 1 -W 1 "$PEER_IP" &>/dev/null; then
    PEER_REACHABLE="Yes"
fi

# Verifier si monte
MOUNTED="No"
if mountpoint -q /mnt/drbd 2>/dev/null; then
    MOUNTED="Yes"
fi

# Couleur du role
ROLE_COLOR=$NC
if [ "$ROLE" == "primary" ]; then
    ROLE_COLOR=$GREEN
elif [ "$ROLE" == "secondary" ]; then
    ROLE_COLOR=$BLUE
fi

# Couleur du state
STATE_COLOR=$NC
if [ "$STATE" == "UpToDate" ]; then
    STATE_COLOR=$GREEN
elif [ "$STATE" == "Inconsistent" ]; then
    STATE_COLOR=$YELLOW
elif [ "$STATE" == "unconfigured" ]; then
    STATE_COLOR=$RED
fi

# Barre de progression
PROGRESS_BAR=""
PROGRESS_FILLED=$((SYNC / 5))
PROGRESS_EMPTY=$((20 - PROGRESS_FILLED))
for ((i=0; i<PROGRESS_FILLED; i++)); do
    PROGRESS_BAR+="█"
done
for ((i=0; i<PROGRESS_EMPTY; i++)); do
    PROGRESS_BAR+="░"
done

# Affichage
echo ""
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│           DRBD STATUS - Resource: r0                        │${NC}"
echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}                                                             ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Node: ${NC}${DRBD_NODE_NAME:-node1} (${NODE_IP})                              ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Role: ${NC}${ROLE_COLOR}${ROLE^^}${NC}                                              ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Disk State: ${NC}${STATE_COLOR}${STATE}${NC}                                      ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Mounted: ${NC}${MOUNTED}                                              ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}                                                             ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Connection${NC}                                                  ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ─────────────                                               ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  Peer: ${PEER_IP}                                         ${CYAN}│${NC}"
if [ "$CONNECTED" == "true" ] && [ "$PEER_REACHABLE" == "Yes" ]; then
    echo -e "${CYAN}│${NC}  Status: ${GREEN}Connected${NC}                                         ${CYAN}│${NC}"
else
    echo -e "${CYAN}│${NC}  Status: ${RED}Disconnected${NC}                                      ${CYAN}│${NC}"
fi
echo -e "${CYAN}│${NC}  Peer Reachable: ${PEER_REACHABLE}                                        ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}                                                             ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Synchronization${NC}                                             ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ───────────────────                                         ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  Progress: [${GREEN}${PROGRESS_BAR}${NC}] ${SYNC}%                 ${CYAN}│${NC}"
if [ "$SYNC" == "100" ]; then
    echo -e "${CYAN}│${NC}  Status: ${GREEN}Fully Synchronized${NC}                                 ${CYAN}│${NC}"
else
    echo -e "${CYAN}│${NC}  Status: ${YELLOW}Synchronizing...${NC}                                   ${CYAN}│${NC}"
fi
echo -e "${CYAN}│${NC}                                                             ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}  ${BLUE}Configuration${NC}                                               ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ─────────────────                                           ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  Protocol: C (Synchronous)                                   ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  Device: /dev/drbd0                                          ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  Backing Disk: /data/drbd-disk.img                           ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  Mount Point: /mnt/drbd                                      ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}                                                             ${CYAN}│${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Resume rapide pour scripts
if [ "$1" == "--brief" ]; then
    echo "ROLE:$ROLE STATE:$STATE SYNC:$SYNC CONNECTED:$CONNECTED"
fi
