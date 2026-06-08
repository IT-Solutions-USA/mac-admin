#!/bin/bash
# =============================================================================
# macos_restore_tdm.sh
#
# Description:
#   Restores macOS to an Intel MacBook's internal disk while connected in
#   Target Disk Mode (TDM) to an Apple Silicon Mac.
#
#   This script handles the key limitation that `startosinstall --volume`
#   does NOT work from Apple Silicon to an Intel target disk. Instead, it uses
#   `createinstallmedia` to write a bootable macOS installer to the target disk,
#   alongside a clean APFS partition ready to receive the macOS installation.
#
# Use Case:
#   - Host machine : Apple Silicon Mac (e.g. Mac mini M4 Pro)
#   - Target machine: Intel Mac with T2 chip (e.g. MacBook Pro 2019)
#   - Connection    : Thunderbolt cable, target booted in Target Disk Mode (hold T)
#
# Result:
#   The target disk will have two partitions:
#     1. "Install macOS <version>"  — ~22 GB HFS+  — bootable installer
#     2. "Macintosh HD"             — remaining GB  — clean APFS install target
#
#   Boot the target Mac holding Option (⌥), select the installer, then install
#   macOS to "Macintosh HD". The SSV seal is created automatically on install.
#
# Requirements:
#   - macOS installer app in /Applications (e.g. "Install macOS Sequoia.app")
#   - Target disk connected and visible via `diskutil list`
#   - Sudo privileges on the host Mac
#
# Usage:
#   sudo ./macos_restore_tdm.sh
#
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

# Path to the macOS installer app
INSTALLER_APP="/Applications/Install macOS Sequoia.app"

# Disk identifier of the target (Intel Mac) disk — e.g. disk4, disk6
# Run `diskutil list` to identify the correct external disk before running
TARGET_DISK="disk4"

# Name for the installer partition (HFS+)
INSTALLER_VOL_NAME="Install macOS Sequoia"

# Size of the installer partition (must be larger than ~18 GB)
INSTALLER_PART_SIZE="22g"

# Name for the macOS installation partition (APFS)
MACOS_VOL_NAME="Macintosh HD"

# macOS version to download if installer is not already present
MACOS_VERSION="15.7.7"

# ─── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run with sudo."
}

# ─── Step 1: Download installer if missing ────────────────────────────────────

download_installer() {
    if [[ -d "$INSTALLER_APP" ]]; then
        log "Installer found: $INSTALLER_APP"
        return
    fi

    log "Installer not found. Downloading macOS $MACOS_VERSION (~15 GB)..."
    softwareupdate --fetch-full-installer --full-installer-version "$MACOS_VERSION" \
        || die "Failed to download macOS installer."
    log "Download complete."
}

# ─── Step 2: Validate target disk ─────────────────────────────────────────────

validate_target_disk() {
    log "Validating target disk: /dev/$TARGET_DISK"

    diskutil list "/dev/$TARGET_DISK" > /dev/null 2>&1 \
        || die "Disk /dev/$TARGET_DISK not found. Connect the target Mac in TDM first."

    local protocol
    protocol=$(diskutil info "/dev/$TARGET_DISK" | grep Protocol | awk '{print $2}')
    log "Disk protocol: $protocol"

    local disk_type
    disk_type=$(diskutil list | grep "$TARGET_DISK" | grep -i "external" || true)
    [[ -n "$disk_type" ]] || warn "Disk does not appear to be external — double-check TARGET_DISK."
}

# ─── Step 3: Erase disk as HFS+ (required for createinstallmedia) ─────────────

format_disk_hfs() {
    log "Erasing /dev/$TARGET_DISK as HFS+ (JHFS+)..."
    diskutil eraseDisk JHFS+ "TempVolume" GPT "/dev/$TARGET_DISK" \
        || die "Failed to erase disk."
    log "Disk erased."
}

# ─── Step 4: Write bootable installer ─────────────────────────────────────────

write_installer() {
    local createinstallmedia="$INSTALLER_APP/Contents/Resources/createinstallmedia"

    [[ -x "$createinstallmedia" ]] \
        || die "createinstallmedia not found at: $createinstallmedia"

    log "Writing bootable installer to /dev/${TARGET_DISK}s2..."
    "$createinstallmedia" --volume "/Volumes/TempVolume" --nointeraction \
        || die "createinstallmedia failed."
    log "Bootable installer written."
}

# ─── Step 5: Split partition — installer + APFS target ────────────────────────

split_partitions() {
    log "Splitting partition: $INSTALLER_PART_SIZE installer + remaining APFS..."

    # After createinstallmedia the installer volume is at <disk>s2
    local installer_part="${TARGET_DISK}s2"
    local installer_mount="/Volumes/$INSTALLER_VOL_NAME"

    # Remount if needed
    diskutil mount "$installer_part" > /dev/null 2>&1 || true

    diskutil splitPartition "$installer_part" 2 \
        JHFS+ "$INSTALLER_VOL_NAME" "$INSTALLER_PART_SIZE" \
        APFS  "$MACOS_VOL_NAME"    "477g" \
        || die "Failed to split partition."
    log "Partition split complete."
}

# ─── Step 6: Re-write installer to the smaller partition ──────────────────────

rewrite_installer() {
    local createinstallmedia="$INSTALLER_APP/Contents/Resources/createinstallmedia"
    local installer_mount="/Volumes/$INSTALLER_VOL_NAME"

    log "Re-writing installer to $installer_mount..."
    "$createinstallmedia" --volume "$installer_mount" --nointeraction \
        || die "Failed to re-write installer."
    log "Installer re-written successfully."
}

# ─── Step 7: Eject disk ───────────────────────────────────────────────────────

eject_disk() {
    log "Ejecting /dev/$TARGET_DISK..."
    diskutil eject "/dev/$TARGET_DISK" || warn "Could not eject disk — eject manually."
    log "Disk ejected safely."
}

# ─── Step 8: Print next steps ─────────────────────────────────────────────────

print_next_steps() {
    echo ""
    echo "============================================================"
    echo "  SUCCESS — Disk is ready"
    echo "============================================================"
    echo ""
    echo "  Next steps on the MacBook Pro:"
    echo ""
    echo "  1. Unplug the Thunderbolt cable"
    echo "  2. Shut down the MacBook Pro completely"
    echo "  3. Power on and hold Option (⌥)"
    echo "  4. Select 'Install macOS Sequoia' in the boot picker"
    echo "  5. In the installer, choose 'Macintosh HD' as the target"
    echo "  6. Complete the installation (~30-40 min, auto-restarts)"
    echo ""
    echo "  Note: The SSV seal is created automatically during install."
    echo "  If a firmware password lock appears, use Apple Configurator 2"
    echo "  on this Mac mini for a DFU restore."
    echo "============================================================"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "============================================================"
    echo "  macOS Restore via Target Disk Mode"
    echo "  Host: Apple Silicon Mac → Target: Intel Mac (T2)"
    echo "============================================================"
    echo ""

    require_root
    download_installer
    validate_target_disk
    format_disk_hfs
    write_installer
    split_partitions
    rewrite_installer
    eject_disk
    print_next_steps
}

main "$@"
