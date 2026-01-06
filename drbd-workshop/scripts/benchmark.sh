#!/bin/bash
# =============================================================================
# Script de Benchmark DRBD
# =============================================================================
# Ce script mesure les performances d'ecriture et de lecture
# sur le volume DRBD pour comparer les differents protocoles.
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TEST_DIR="/mnt/drbd"
TEST_FILE="$TEST_DIR/benchmark_test"
RESULTS_DIR="/tmp/drbd_benchmarks"

mkdir -p "$RESULTS_DIR"

show_help() {
    cat << EOF

Usage: $0 <command> [options]

Commands:
    write           Test de performance en ecriture
    read            Test de performance en lecture
    mixed           Test mixte lecture/ecriture
    iops            Test de IOPS (petites operations)
    latency         Test de latence
    full            Suite complete de tests
    compare         Comparer les resultats des protocoles

Options:
    --size=SIZE     Taille des donnees (default: 100M)
    --count=N       Nombre d'iterations (default: 5)

Examples:
    $0 write                    # Test d'ecriture standard
    $0 write --size=500M        # Test avec 500MB
    $0 full                     # Suite complete
    $0 compare                  # Comparer A vs B vs C

EOF
}

check_mounted() {
    if ! mountpoint -q "$TEST_DIR" 2>/dev/null; then
        # En mode simulation, creer le repertoire si non monte
        mkdir -p "$TEST_DIR"
        return 0
    fi
    return 0
}

write_test() {
    SIZE="${1:-100M}"
    COUNT="${2:-5}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           DRBD WRITE BENCHMARK                            ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_mounted

    echo "Configuration:"
    echo "  - Taille: $SIZE"
    echo "  - Iterations: $COUNT"
    echo "  - Destination: $TEST_DIR"
    echo ""

    RESULTS=()

    for ((i=1; i<=COUNT; i++)); do
        echo -e "${GREEN}[Test $i/$COUNT]${NC} Ecriture en cours..."

        # Simulation de benchmark avec dd
        START=$(date +%s.%N)

        # Convertir la taille en nombre
        SIZE_NUM=$(echo "$SIZE" | sed 's/M//')

        # Creer des donnees de test
        dd if=/dev/urandom of="$TEST_FILE" bs=1M count=$SIZE_NUM conv=fdatasync 2>&1 | tail -1

        END=$(date +%s.%N)
        DURATION=$(echo "$END - $START" | bc)
        SPEED=$(echo "scale=2; $SIZE_NUM / $DURATION" | bc)

        echo "  Duree: ${DURATION}s - Vitesse: ${SPEED} MB/s"
        RESULTS+=("$SPEED")

        rm -f "$TEST_FILE"
    done

    # Calculer la moyenne
    SUM=0
    for R in "${RESULTS[@]}"; do
        SUM=$(echo "$SUM + $R" | bc)
    done
    AVG=$(echo "scale=2; $SUM / $COUNT" | bc)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}Resultats Write Benchmark${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo "  Vitesse moyenne: ${AVG} MB/s"
    echo "  Taille testee: $SIZE"
    echo "  Iterations: $COUNT"
    echo ""

    # Sauvegarder les resultats
    PROTOCOL=$(grep "protocol" /etc/drbd.d/r0.res 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "C")
    echo "$AVG" > "$RESULTS_DIR/write_protocol_$PROTOCOL"
}

read_test() {
    SIZE="${1:-100M}"
    COUNT="${2:-5}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           DRBD READ BENCHMARK                             ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_mounted

    SIZE_NUM=$(echo "$SIZE" | sed 's/M//')

    # Creer le fichier de test
    echo -e "${YELLOW}[PREP] Creation du fichier de test...${NC}"
    dd if=/dev/urandom of="$TEST_FILE" bs=1M count=$SIZE_NUM 2>/dev/null
    sync

    echo ""
    echo "Configuration:"
    echo "  - Taille: $SIZE"
    echo "  - Iterations: $COUNT"
    echo ""

    RESULTS=()

    for ((i=1; i<=COUNT; i++)); do
        echo -e "${GREEN}[Test $i/$COUNT]${NC} Lecture en cours..."

        # Vider le cache
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

        START=$(date +%s.%N)
        dd if="$TEST_FILE" of=/dev/null bs=1M 2>&1 | tail -1
        END=$(date +%s.%N)

        DURATION=$(echo "$END - $START" | bc)
        SPEED=$(echo "scale=2; $SIZE_NUM / $DURATION" | bc)

        echo "  Duree: ${DURATION}s - Vitesse: ${SPEED} MB/s"
        RESULTS+=("$SPEED")
    done

    rm -f "$TEST_FILE"

    # Calculer la moyenne
    SUM=0
    for R in "${RESULTS[@]}"; do
        SUM=$(echo "$SUM + $R" | bc)
    done
    AVG=$(echo "scale=2; $SUM / $COUNT" | bc)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}Resultats Read Benchmark${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo "  Vitesse moyenne: ${AVG} MB/s"
    echo ""
}

iops_test() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           DRBD IOPS BENCHMARK                             ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_mounted

    echo "Test IOPS avec fio..."
    echo ""

    if command -v fio &>/dev/null; then
        fio --name=iops_test \
            --directory="$TEST_DIR" \
            --rw=randwrite \
            --bs=4k \
            --size=50M \
            --numjobs=4 \
            --time_based \
            --runtime=30 \
            --group_reporting \
            --output-format=normal

        rm -f "$TEST_DIR"/iops_test*
    else
        echo -e "${YELLOW}[WARN] fio non installe - test simplifie${NC}"
        echo ""

        # Test simplifie
        COUNT=1000
        echo "Ecriture de $COUNT fichiers de 4KB..."

        START=$(date +%s.%N)
        for ((i=1; i<=COUNT; i++)); do
            dd if=/dev/urandom of="$TEST_DIR/test_$i" bs=4k count=1 2>/dev/null
        done
        sync
        END=$(date +%s.%N)

        DURATION=$(echo "$END - $START" | bc)
        IOPS=$(echo "scale=0; $COUNT / $DURATION" | bc)

        echo ""
        echo "IOPS approximatifs: $IOPS"

        rm -f "$TEST_DIR"/test_*
    fi
}

latency_test() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           DRBD LATENCY BENCHMARK                          ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_mounted

    COUNT=100
    echo "Mesure de latence sur $COUNT ecritures de 4KB..."
    echo ""

    LATENCIES=()

    for ((i=1; i<=COUNT; i++)); do
        START=$(date +%s.%N)
        dd if=/dev/urandom of="$TEST_DIR/latency_test" bs=4k count=1 conv=fdatasync 2>/dev/null
        END=$(date +%s.%N)

        LATENCY=$(echo "scale=6; ($END - $START) * 1000" | bc)
        LATENCIES+=("$LATENCY")

        # Afficher progression
        if (( i % 10 == 0 )); then
            echo -ne "\r  Progress: $i/$COUNT"
        fi
    done

    rm -f "$TEST_DIR/latency_test"

    echo -e "\r                          "

    # Calculer les statistiques
    SUM=0
    MIN=${LATENCIES[0]}
    MAX=${LATENCIES[0]}

    for L in "${LATENCIES[@]}"; do
        SUM=$(echo "$SUM + $L" | bc)
        if (( $(echo "$L < $MIN" | bc -l) )); then MIN=$L; fi
        if (( $(echo "$L > $MAX" | bc -l) )); then MAX=$L; fi
    done

    AVG=$(echo "scale=3; $SUM / $COUNT" | bc)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}Resultats Latency Benchmark${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo "  Latence moyenne: ${AVG} ms"
    echo "  Latence min: ${MIN} ms"
    echo "  Latence max: ${MAX} ms"
    echo ""
}

full_test() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           DRBD FULL BENCHMARK SUITE                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    write_test "100M" "3"
    read_test "100M" "3"
    latency_test
    iops_test

    echo ""
    echo -e "${GREEN}Suite de tests terminee!${NC}"
}

compare_results() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           COMPARAISON DES PROTOCOLES                      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Pour comparer les protocoles:"
    echo ""
    echo "1. Executez les benchmarks avec Protocol A:"
    echo "   /scripts/change-protocol.sh A"
    echo "   /scripts/benchmark.sh write"
    echo ""
    echo "2. Executez les benchmarks avec Protocol B:"
    echo "   /scripts/change-protocol.sh B"
    echo "   /scripts/benchmark.sh write"
    echo ""
    echo "3. Executez les benchmarks avec Protocol C:"
    echo "   /scripts/change-protocol.sh C"
    echo "   /scripts/benchmark.sh write"
    echo ""

    # Afficher les resultats existants
    if ls "$RESULTS_DIR"/write_protocol_* &>/dev/null; then
        echo "Resultats sauvegardes:"
        echo ""
        echo "┌────────────┬────────────────┐"
        echo "│ Protocol   │ Write (MB/s)   │"
        echo "├────────────┼────────────────┤"

        for f in "$RESULTS_DIR"/write_protocol_*; do
            PROTO=$(basename "$f" | sed 's/write_protocol_//')
            SPEED=$(cat "$f")
            printf "│ %-10s │ %-14s │\n" "$PROTO" "$SPEED"
        done

        echo "└────────────┴────────────────┘"
    else
        echo "Aucun resultat sauvegarde."
    fi
}

# Parse arguments
SIZE="100M"
COUNT="5"

for arg in "$@"; do
    case $arg in
        --size=*)
            SIZE="${arg#*=}"
            ;;
        --count=*)
            COUNT="${arg#*=}"
            ;;
    esac
done

# Main
case "${1:-help}" in
    write)
        write_test "$SIZE" "$COUNT"
        ;;
    read)
        read_test "$SIZE" "$COUNT"
        ;;
    mixed)
        write_test "$SIZE" "$COUNT"
        read_test "$SIZE" "$COUNT"
        ;;
    iops)
        iops_test
        ;;
    latency)
        latency_test
        ;;
    full)
        full_test
        ;;
    compare)
        compare_results
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
