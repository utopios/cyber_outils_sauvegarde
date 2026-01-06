#!/bin/bash
# =============================================================================
# Entrypoint pour DRBD Node
# =============================================================================

set -e

echo "=============================================="
echo "  DRBD Workshop - Node: ${DRBD_NODE_NAME}"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  - Node IP: ${DRBD_NODE_IP}"
echo "  - Peer IP: ${DRBD_PEER_IP}"
echo "  - DRBD Port: ${DRBD_PORT}"
echo "  - Resource: ${DRBD_RESOURCE}"
echo ""

# Creer le fichier hosts
echo "${DRBD_NODE_IP} node1" >> /etc/hosts
echo "${DRBD_PEER_IP} node2" >> /etc/hosts

# Initialiser le repertoire de donnees
if [ ! -f /data/drbd-disk.img ]; then
    echo "Creation du fichier disque DRBD..."
    dd if=/dev/zero of=/data/drbd-disk.img bs=1M count=0 seek=1024
fi

# Creer le repertoire de montage
mkdir -p /mnt/drbd

# Message de bienvenue
cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════╗
║                    DRBD WORKSHOP - LAB ENVIRONMENT                ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  Commandes disponibles:                                           ║
║                                                                   ║
║  /scripts/drbd-init.sh       - Initialiser DRBD                   ║
║  /scripts/drbd-status.sh     - Voir le status                     ║
║  /scripts/drbd-role.sh       - Changer de role                    ║
║  /scripts/monitor.sh         - Monitoring temps reel              ║
║  /scripts/benchmark.sh       - Lancer des benchmarks              ║
║  /scripts/failover.sh        - Effectuer un failover              ║
║  /scripts/simulate-latency.sh - Simuler latence reseau            ║
║  /scripts/simulate-failure.sh - Simuler des pannes                ║
║                                                                   ║
║  Pour commencer: /scripts/drbd-init.sh create-md                  ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF

# Executer la commande passee en argument
exec "$@"
