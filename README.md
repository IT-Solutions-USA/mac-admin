# Mac Admin Scripts

A collection of macOS administration and restore scripts for Apple Silicon and Intel Macs.

---

## Scripts

### 1. `macos_restore_tdm.sh` — macOS Restore via Target Disk Mode

**The most important script in this collection.**

#### Problem it solves

MacBook Pro 2019 (and other Intel Macs with the T2 security chip) can reach a state where:

- **The SSV seal is broken** — macOS uses a cryptographic Signed System Volume (SSV) seal introduced in Big Sur. If the seal is broken (due to failed updates, system file modifications, or corruption), macOS will **refuse to boot**.
- **Cmd+R Recovery fails** — On T2 Macs with a broken seal or corrupted firmware, holding `Cmd+R` at startup may not load Recovery. The Mac simply shows a globe, spins forever, or displays a lock icon.
- **Internet Recovery also fails** — Apple's servers validate the T2 chip before allowing Internet Recovery. A broken seal can cause this validation to fail, making it **impossible to reinstall macOS the normal way**.

This is a known issue with MacBook Pro 2016–2019 (T1/T2 chip) machines.

#### Why `startosinstall --volume` doesn't work

If you try to install macOS from an Apple Silicon Mac (M1/M2/M3/M4) to an Intel Mac's disk in Target Disk Mode, `startosinstall --volume` will silently fail and print its usage text. This is because:

1. Apple Silicon Macs use a different security architecture (SPSB / LocalPolicy)
2. `startosinstall` is restricted from installing to external volumes from Apple Silicon hosts
3. The Intel disk's T2 security policy is not accessible from the host Mac's `startosinstall`

#### Solution

Use `createinstallmedia` to write a **bootable macOS installer** directly onto the Intel Mac's own disk. The installer is Apple-signed and bypasses the T2 restrictions. Then boot the Intel Mac from its own disk to install macOS fresh.

#### Requirements

| Requirement | Detail |
|---|---|
| Host Mac | Apple Silicon Mac (M1 or later) |
| Target Mac | Intel Mac with T2 chip (MacBook Pro 2016–2019, MacBook Air 2018–2019, etc.) |
| Connection | Thunderbolt cable, target Mac booted in **Target Disk Mode** (hold `T` at startup) |
| Disk space | ~15 GB free on host for the installer download |
| Permissions | Sudo on the host Mac |

#### What the script does

1. **Downloads** macOS Sequoia 15.7.7 installer if not already present (~15 GB)
2. **Erases** the target disk as HFS+ (required — `createinstallmedia` does not support APFS)
3. **Writes** the bootable macOS installer to the full disk
4. **Splits** the disk into two partitions:
   - `Install macOS Sequoia` — 22 GB HFS+ (bootable installer)
   - `Macintosh HD` — ~477 GB APFS (clean install target)
5. **Re-writes** the installer to the smaller partition
6. **Ejects** the disk safely

#### Usage

```bash
# Edit the TARGET_DISK variable in the script to match your external disk
# Run `diskutil list` to identify it (look for the external Thunderbolt disk)

sudo ./macos_restore_tdm.sh
```

#### After the script completes

1. Unplug the Thunderbolt cable from the Intel Mac
2. Shut it down completely
3. Power on while holding **Option (⌥)**
4. Select **"Install macOS Sequoia"** in the boot picker
5. In the installer, select **"Macintosh HD"** as the destination
6. Installation takes ~30–40 minutes with automatic restarts
7. The **SSV seal is created automatically** — no extra steps needed

> **If a lock icon appears at the boot picker:** This is a T2 firmware password, not a disk issue. Use **Apple Configurator 2** on the host Mac mini for a DFU restore, which reflashes the T2 chip and removes the firmware password.

---

### 2. `check_partitions.sh` — Disk & Partition Overview

Displays a clean summary of all disks, APFS containers, and external drives.

```bash
./check_partitions.sh
```

---

## Setup

```bash
git clone https://github.com/ikonstas70/mac-admin.git
cd mac-admin
chmod +x *.sh
```

---

## Background: The T2 Seal Problem

The **Signed System Volume (SSV)** seal was introduced in macOS Big Sur (11.0). It creates a cryptographic hash of every file in the System volume. On boot, the T2 chip verifies this seal. If it doesn't match:

- The Mac refuses to boot into macOS
- Recovery mode may also be inaccessible if the T2 firmware itself is affected
- Internet Recovery can fail if Apple's servers cannot validate the device

**Common causes of a broken seal on MacBook Pro 2016–2019:**
- Failed macOS upgrade
- Third-party kernel extensions or system modifications
- Interrupted firmware update
- Disk corruption

**The only reliable fix** for a T2 Mac with a broken seal where Recovery is inaccessible is to install macOS from a bootable external source — which is exactly what this script automates.

---

## Tested On

| Host | Target | macOS Version | Result |
|---|---|---|---|
| Mac mini M4 Pro (Mac16,11) | MacBook Pro 16" 2019 | Sequoia 15.7.7 | ✅ Success |

---

## Author

ikonstas70 — [GitHub](https://github.com/ikonstas70)
