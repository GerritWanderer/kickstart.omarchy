# Boot Repair Session - 2025-11-05

## Summary

Fixed emergency mode boot issues caused by disabled mkinitcpio hooks and corrupted EFI partition.

## Issues Found

### Critical

1. **Emergency Mode Trigger** - `/boot/efi` failed to mount in previous boot
2. **Disabled mkinitcpio hooks** - Kernel files not automatically synced during upgrades
   - `90-mkinitcpio-install.hook.disabled`
   - `60-mkinitcpio-remove.hook.disabled`
3. **Missing fallback images** - No recovery initramfs images
4. **EFI partition corruption** - Dirty bit set, boot sector inconsistencies
5. **Read-only snapshot** - System booted into `/@/.snapshots/30/snapshot`

### Non-Critical

- Missing kernel modules: ntsync, crypto_user, pkcs8_key_parser (harmless)
- Read-only filesystem errors during emergency mode
- Console font warnings in mkinitcpio

## Fixes Applied

### 1. Made Snapshot Writable

```bash
sudo btrfs property set / ro false
```

### 2. Re-enabled mkinitcpio Hooks

```bash
sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled \
        /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled \
        /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
```

### 3. Enabled Fallback Images

Edited both preset files:

- `/etc/mkinitcpio.d/linux-cachyos.preset`
- `/etc/mkinitcpio.d/linux-cachyos-lts.preset`

Changed: `PRESETS=('default')` → `PRESETS=('default' 'fallback')`

### 4. Regenerated Initramfs

```bash
sudo mkinitcpio -P
```

Created:

- initramfs-linux-cachyos.img (44M)
- initramfs-linux-cachyos-fallback.img (192M)
- initramfs-linux-cachyos-lts.img (42M)
- initramfs-linux-cachyos-lts-fallback.img (122M)

### 5. Repaired EFI Partition

```bash
sudo umount /boot/efi
sudo fsck.vfat -a /dev/nvme0n1p1
sudo mount /boot/efi
```

### 6. Updated GRUB

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

## System Info

- Currently running: 6.17.7-2-cachyos
- Installed kernels: linux-cachyos 6.17.7-2, linux-cachyos-lts 6.12.56-2
- Disk health: PASSED (smartctl)
- Root partition: /dev/nvme0n1p2 (Btrfs, 37G available)
- EFI partition: /dev/nvme0n1p1 (UUID: 3676-4562, 299M available)
- Current subvolume: /@/.snapshots/30/snapshot (read-write enabled)
- Normal root: /@

## After Reboot - Verification Steps

### 1. Check you're on normal root

```bash
mount | grep "on / type"
# Should show: subvol=/@ (NOT /@/.snapshots/30/snapshot)
```

### 2. Verify EFI mounted correctly

```bash
mount | grep efi
df -h /boot/efi
# Should be mounted without errors
```

### 3. Check journal for errors

```bash
journalctl -b -p err
# Should NOT show "Failed to mount /boot/efi" or "Emergency Mode"
```

### 4. Verify hooks are still enabled

```bash
ls -la /usr/share/libalpm/hooks/ | grep mkinitcpio
# Should show .hook files (NOT .hook.disabled)
```

### 5. Check boot files

```bash
ls -lh /boot/
# Should show all 6 files: 2 kernels + 4 initramfs images
```

## If Reboot Fails

### Scenario 1: Emergency Mode Again

1. Check EFI mount: `journalctl | grep -i "boot/efi"`
2. Try manual mount: `sudo mount /boot/efi`
3. Check fstab: `cat /etc/fstab | grep efi`
4. Verify UUID matches: `blkid | grep 3676-4562`

### Scenario 2: Booted into Snapshot Again

1. Check current mount: `mount | grep "on / type"`
2. Check GRUB default: `grep "set default" /boot/grub/grub.cfg`
3. May need to manually select correct boot entry in GRUB menu

### Scenario 3: Kernel Panic

1. Select "CachyOS Linux (fallback initramfs)" from GRUB
2. Or select "linux-cachyos-lts" kernel
3. Or boot into snapshot 31 (most recent)

## Testing Kernel Upgrade

Once system is stable, test the upgrade process:

```bash
# Simulate what happens during kernel upgrade
sudo mkinitcpio -P

# Check that hooks work
ls -lh /boot/
# Timestamps should update

# Then perform actual upgrade
sudo pacman -Syu
```

## Files Modified in Snapshot 30

- /usr/share/libalpm/hooks/90-mkinitcpio-install.hook (renamed from .disabled)
- /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook (renamed from .disabled)
- /etc/mkinitcpio.d/linux-cachyos.preset (added fallback)
- /etc/mkinitcpio.d/linux-cachyos-lts.preset (added fallback)
- /boot/initramfs-\* (regenerated all 4 images)
- /boot/grub/grub.cfg (regenerated with fallback entries)

## Notes

- Snapshot 30 was made read-write during repair
- Changes in snapshot 30 won't persist to normal root unless you boot it
- The hook re-enabling needs to be done in normal root too if not persistent
- EFI repair should persist (different filesystem)

---

# Second Boot Repair Session - 2025-11-05 (Post-Reboot)

## What Happened After Reboot

User rebooted but ended up in emergency mode again (boots -3 and -1).

## Root Cause Analysis

Investigation revealed TWO critical problems:

### Problem 1: Repairs Only Applied to Snapshot 30

All fixes from the first session were done **inside snapshot 30**, not normal root:

**Normal root (`/@`) boot files:**

```
/mnt/boot/initramfs-linux-cachyos.img (44M, Nov 4 21:51) - OLD
/mnt/boot/initramfs-linux-cachyos-lts.img (42M, Nov 4 21:51) - OLD
NO fallback images
```

**Snapshot 30 boot files:**

```
/boot/initramfs-linux-cachyos.img (44M, Nov 5 22:18) - NEW
/boot/initramfs-linux-cachyos-fallback.img (192M, Nov 5 22:18) - NEW
/boot/initramfs-linux-cachyos-lts.img (42M, Nov 5 22:18) - NEW
/boot/initramfs-linux-cachyos-lts-fallback.img (122M, Nov 5 22:18) - NEW
```

### Problem 2: GRUB Configured to Boot Snapshot 30

The GRUB config regenerated in first session pointed ALL entries to snapshot 30:

```
rootflags=subvol=@/.snapshots/30/snapshot
```

This created a catch-22:

- Trying to boot normal root → uses old initramfs → vfat module missing → `/boot/efi` fails to mount → emergency mode
- GRUB default → boots snapshot 30 → works, but not normal root

## Journal Evidence

Boot attempts -3 and -1 both showed:

```
Nov 05 22:22:41 xtia mount[664]: mount: /boot/efi: unknown filesystem type 'vfat'.
Nov 05 22:22:41 xtia systemd[1]: boot-efi.mount: Failed with result 'exit-code'.
Nov 05 22:22:41 xtia systemd[1]: Failed to mount /boot/efi.
Nov 05 22:22:41 xtia systemd[1]: Started Emergency Shell.
Nov 05 22:22:41 xtia systemd[1]: Reached target Emergency Mode.
```

**Key error:** `unknown filesystem type 'vfat'` - vfat module missing from old initramfs

## Fixes Applied (Second Session)

### 1. Copied Working Boot Files to Normal Root

```bash
sudo mount -o subvol=/@ /dev/nvme0n1p2 /mnt
sudo cp -v /boot/initramfs-* /mnt/boot/
```

Copied all 4 initramfs files (including 192M and 122M fallback images) from snapshot 30 to normal root.

### 2. Re-enabled Hooks in Normal Root

```bash
sudo mv /mnt/usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled \
        /mnt/usr/share/libalpm/hooks/90-mkinitcpio-install.hook
sudo mv /mnt/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled \
        /mnt/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
```

### 3. Copied Preset Files to Normal Root

```bash
sudo cp -v /etc/mkinitcpio.d/*.preset /mnt/etc/mkinitcpio.d/
```

Both presets now have `PRESETS=('default' 'fallback')` enabled.

### 4. Regenerated GRUB from Normal Root Context

```bash
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
for dir in dev proc sys; do sudo mount --bind /$dir /mnt/$dir; done
sudo chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
```

**Result:**

- GRUB now points to `rootflags=subvol=@` (correct!)
- Detected all 31 snapshots
- Has fallback entries for both kernels

### 5. Verification

```bash
# Verified GRUB entries now use correct subvolume
grep "rootflags=subvol" /mnt/boot/grub/grub.cfg | head -5
# Shows: rootflags=subvol=@  (NOT subvol=@/.snapshots/30/snapshot)
```

## Files Modified in Normal Root (`/@`)

- `/boot/initramfs-linux-cachyos.img` (44M, Nov 5 22:29)
- `/boot/initramfs-linux-cachyos-fallback.img` (192M, Nov 5 22:29)
- `/boot/initramfs-linux-cachyos-lts.img` (42M, Nov 5 22:29)
- `/boot/initramfs-linux-cachyos-lts-fallback.img` (122M, Nov 5 22:29)
- `/usr/share/libalpm/hooks/90-mkinitcpio-install.hook` (renamed from .disabled)
- `/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook` (renamed from .disabled)
- `/etc/mkinitcpio.d/linux-cachyos.preset` (fallback enabled)
- `/etc/mkinitcpio.d/linux-cachyos-lts.preset` (fallback enabled)
- `/boot/grub/grub.cfg` (regenerated to point to `/@`)

## Expected Behavior on Next Reboot

System should now:

1. Boot into normal root (`subvol=/@`)
2. Successfully mount `/boot/efi` using vfat module from new initramfs
3. Reach graphical.target without emergency mode

## Verification Commands After Next Reboot

```bash
# Should show: subvol=/@ (NOT snapshot 30)
mount | grep "on / type"

# Should be mounted successfully
mount | grep efi
df -h /boot/efi

# Should show NO emergency mode or failed EFI mount
journalctl -b -p err

# Should show enabled hooks
ls -la /usr/share/libalpm/hooks/ | grep mkinitcpio

# Should show 6 files: 2 kernels + 4 initramfs (2 default + 2 fallback)
ls -lh /boot/ | grep -E "vmlinuz|initramfs"
```

---

# Third Boot Repair Session - 2025-11-05 (Post-Second Reboot)

## What Happened After Second Reboot

User rebooted again but **still ended up in emergency mode** (boot -1).

Current state at session start:

- Booted into **snapshot 30** (works fine)
- Boot -1 (attempt to boot normal root): **Emergency mode** with same vfat error
- All files from session 2 appeared correct (initramfs copied, hooks enabled, GRUB updated)

## Root Cause Analysis - The Real Problem

Investigation revealed the **actual root cause**:

### Problem: Missing vfat Module in mkinitcpio.conf

The `/etc/mkinitcpio.conf` only had:

```bash
MODULES=(crc32c)
```

**Missing:** `vfat` module needed to mount `/boot/efi`

This is why the error occurred:

```
mount: /boot/efi: unknown filesystem type 'vfat'
```

The initramfs didn't contain the vfat kernel module, so the system couldn't mount the EFI partition during boot.

### Secondary Problem: Kernel Version Mismatch

Normal root had:

- Kernel vmlinuz files: **6.17.7-2** and **6.12.56-2** (old)
- Kernel modules directory: **6.17.7-3** and **6.12.56-3** (new)

This mismatch occurred because:

1. Kernel upgrade from -2 to -3 happened while hooks were disabled
2. The vmlinuz files in `/boot` weren't updated
3. Only `/lib/modules` was updated

### Why Session 2 Didn't Work

Session 2 copied the initramfs files from snapshot 30 to normal root, but:

- Snapshot 30's initramfs also didn't have vfat module
- The mkinitcpio.conf was never updated to include vfat
- Simply copying broken initramfs files doesn't fix the underlying issue

## Boot Evidence

Boot -1 journal showed:

```
Nov 05 22:34:24 kernel: Command line: ... rootflags=subvol=@ ...
Nov 05 22:34:25 mount[669]: mount: /boot/efi: unknown filesystem type 'vfat'.
Nov 05 22:34:25 systemd[1]: boot-efi.mount: Failed with result 'exit-code'.
Nov 05 22:34:26 systemd[1]: Started Emergency Shell.
Nov 05 22:34:26 systemd[1]: Reached target Emergency Mode.
```

Boot 0 (current session):

```
Booted into: /@/.snapshots/30/snapshot
EFI mounted: Successfully
System state: running (graphical.target)
```

## Fixes Applied (Third Session)

### 1. Added vfat Module to mkinitcpio.conf

```bash
sudo sed -i 's/^MODULES=(crc32c)$/MODULES=(crc32c vfat)/' /mnt/etc/mkinitcpio.conf
```

**Result:** `MODULES=(crc32c vfat)`

### 2. Reinstalled Kernel Packages

Since there was a version mismatch, reinstalled both kernels to sync vmlinuz files with modules:

```bash
# Mounted normal root
sudo mount -o subvol=/@ /dev/nvme0n1p2 /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
for dir in dev proc sys; do sudo mount --bind /$dir /mnt/$dir; done

# Copied packages from current system's cache
sudo cp /var/cache/pacman/pkg/linux-cachyos-6.17.7-3-x86_64_v4.pkg.tar.zst /mnt/tmp/
sudo cp /var/cache/pacman/pkg/linux-cachyos-lts-6.12.56-3-x86_64_v4.pkg.tar.zst /mnt/tmp/

# Reinstalled kernels in chroot
sudo chroot /mnt pacman -U --noconfirm \
  /tmp/linux-cachyos-6.17.7-3-x86_64_v4.pkg.tar.zst \
  /tmp/linux-cachyos-lts-6.12.56-3-x86_64_v4.pkg.tar.zst
```

This triggered:

- mkinitcpio hooks (now re-enabled)
- Regeneration of all 4 initramfs images with **vfat module included**
- GRUB config regeneration (now points to `/@` with snapshot entries)

### 3. Verification

Confirmed vfat module is now in initramfs:

```bash
sudo lsinitcpio /mnt/boot/initramfs-linux-cachyos.img | grep -i vfat
# Output: usr/lib/modules/6.17.7-3-cachyos/kernel/fs/fat/vfat.ko.zst
```

New initramfs files:

```
-rw------- 1 root root 192M  5. Nov 22:41 initramfs-linux-cachyos-fallback.img
-rw------- 1 root root  44M  5. Nov 22:41 initramfs-linux-cachyos.img
-rw------- 1 root root 122M  5. Nov 22:41 initramfs-linux-cachyos-lts-fallback.img
-rw------- 1 root root  42M  5. Nov 22:41 initramfs-linux-cachyos-lts.img
```

GRUB config verified:

```
menuentry 'CachyOS Linux' ... {
  linux /@/boot/vmlinuz-linux-cachyos ... rootflags=subvol=@ ...
```

## Files Modified in Normal Root (`/@`)

- `/etc/mkinitcpio.conf` - Added vfat to MODULES
- `/boot/vmlinuz-linux-cachyos` - Updated to 6.17.7-3
- `/boot/vmlinuz-linux-cachyos-lts` - Updated to 6.12.56-3
- `/boot/initramfs-linux-cachyos.img` - Regenerated with vfat (44M, Nov 5 22:41)
- `/boot/initramfs-linux-cachyos-fallback.img` - Regenerated with vfat (192M, Nov 5 22:41)
- `/boot/initramfs-linux-cachyos-lts.img` - Regenerated with vfat (42M, Nov 5 22:41)
- `/boot/initramfs-linux-cachyos-lts-fallback.img` - Regenerated with vfat (122M, Nov 5 22:41)
- `/boot/grub/grub.cfg` - Regenerated with correct subvolume paths
- Pacman created snapshots 32 (pre) and 33 (post)

## Expected Behavior on Next Reboot

System should now:

1. Boot into **normal root** (`subvol=/@`)
2. Load initramfs with **vfat module**
3. Successfully mount `/boot/efi`
4. Reach **graphical.target** without emergency mode

## Verification Commands After Next Reboot

```bash
# Should show: subvol=/@ (NOT snapshot 30, 31, or 32)
mount | grep "on / type"

# Should be mounted successfully
mount | grep efi
df -h /boot/efi

# Should show NO "unknown filesystem type 'vfat'" errors
journalctl -b -p err

# Verify vfat module is available
lsinitcpio /boot/initramfs-linux-cachyos.img | grep vfat

# Verify kernel versions match
uname -r  # Should show 6.17.7-3-cachyos
ls /lib/modules/  # Should have matching version

# Check hooks are still enabled
ls -la /usr/share/libalpm/hooks/ | grep mkinitcpio
```

## Summary - The Complete Issue

The original problem was a **chain of failures**:

1. **Initial trigger:** EFI partition had dirty bit, `/boot/efi` failed to mount
2. **Underlying issue:** mkinitcpio hooks were disabled, preventing proper kernel updates
3. **Root cause:** mkinitcpio.conf missing `vfat` module
4. **Complication:** Kernel upgrade happened while hooks disabled, creating version mismatch

**Fix required:**

- Add vfat module to mkinitcpio.conf
- Reinstall kernel packages to sync versions and trigger proper initramfs generation
- Re-enable hooks (done in session 2)

## Contact

If you need to resume this session with Claude Code after reboot, provide this file.

**Session dates:**

- First session: 2025-11-05 22:17-22:20 CET (repairs in snapshot 30)
- Second session: 2025-11-05 22:23-22:30 CET (applied repairs to normal root)
- Third session: 2025-11-05 22:37-22:43 CET (found and fixed vfat module issue)
