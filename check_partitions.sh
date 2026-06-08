#!/bin/bash
# =============================================================================
# check_partitions.sh
#
# Description:
#   Displays a clean, human-readable summary of all disks and partitions
#   on the system, including external disks connected via Thunderbolt or USB.
#   Highlights disk type, size, protocol, and APFS volume details.
#
# Usage:
#   ./check_partitions.sh
#
# =============================================================================

set -euo pipefail

log() { echo "[INFO]  $*"; }

echo ""
echo "============================================================"
echo "  Disk & Partition Overview"
echo "  $(date)"
echo "============================================================"
echo ""

# Full disk list
diskutil list

echo ""
echo "============================================================"
echo "  APFS Containers"
echo "============================================================"
echo ""

# Show all APFS containers
diskutil apfs list 2>/dev/null || echo "  No APFS containers found."

echo ""
echo "============================================================"
echo "  External Disks"
echo "============================================================"
echo ""

# List only external disks with details
EXTERNAL=$(diskutil list | grep "external, physical" | awk '{print $1}')

if [[ -z "$EXTERNAL" ]]; then
    echo "  No external disks connected."
else
    for disk in $EXTERNAL; do
        echo "  Disk: $disk"
        diskutil info "$disk" | grep -E "Device Node|Protocol|Media Name|Disk Size|Solid State|SMART" | sed 's/^/    /'
        echo ""
    done
fi
