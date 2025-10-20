# Alpine GRUB Boot Fix

**Critical fix required for Alpine Linux VMs on UTM to boot properly.**

## The Problem

After installing Alpine Linux and rebooting, you may see errors like:

```
error: ../../grub-core/script/function.c:119:can't find command `['.
error: ../../grub-core/script/function.c:119:can't find command `echo'.
```

The VM will still boot, but these errors indicate GRUB is trying to execute commands before loading the required modules.

**This affects:** All Alpine Linux installations on UTM using GRUB
**Impact:** Boot errors (non-fatal but should be fixed)
**Fix time:** ~2 minutes

## Why This Happens

Alpine's `grub-install --removable` creates `BOOTAA64.EFI` with an **embedded configuration** that loads `/boot/grub/grub.cfg` directly.

However, Alpine's auto-generated `/boot/grub/grub.cfg` starts with commands like `[` (test) and `echo` before loading the modules that provide those commands.

**Alpine-specific quirk:** Unlike other distributions, Alpine's GRUB configuration bypasses the standard shim approach and requires module loading commands to be prepended to the main config file.

## The Solution

Prepend module loading commands to `/boot/grub/grub.cfg` before the auto-generated content.

### Manual Fix

**SSH into your Alpine VM:**

```bash
ssh -i ~/.ssh/id_ed25519_alpine_vm root@<VM-IP>
```

**Create the fix script:**

```bash
cat > /tmp/fix-grub.sh << 'EOF'
#!/bin/sh
# Alpine GRUB module loading fix

GRUB_CFG="/boot/grub/grub.cfg"
GRUB_CFG_BACKUP="/boot/grub/grub.cfg.backup"

# Backup original
cp "$GRUB_CFG" "$GRUB_CFG_BACKUP"

# Prepend module loading to existing config
cat > "$GRUB_CFG" << 'MODULES'
# Load required modules before config
insmod part_gpt
insmod part_msdos
insmod fat
insmod ext2
insmod test
insmod echo
insmod normal
MODULES

# Append original config (skip first 8 header lines)
tail -n +9 "$GRUB_CFG_BACKUP" >> "$GRUB_CFG"

echo "GRUB config fixed. Reboot to verify."
EOF

chmod +x /tmp/fix-grub.sh
```

**Run the fix:**

```bash
/tmp/fix-grub.sh
```

**Reboot and verify:**

```bash
reboot
```

After reboot, you should see a clean GRUB menu without error messages.

### What the Fix Does

The script prepends these module loading commands to `/boot/grub/grub.cfg`:

```bash
insmod part_gpt      # GPT partition table support
insmod part_msdos    # MBR partition table support
insmod fat           # FAT filesystem (ESP partition)
insmod ext2          # ext2/ext3/ext4 filesystem
insmod test          # Provides [ and other conditionals
insmod echo          # Provides echo command
insmod normal        # Provides normal boot flow
```

These `insmod` commands are built-in and work without any modules loaded, solving the chicken-and-egg problem.

## Verification

Check the fixed config:

```bash
head -20 /boot/grub/grub.cfg
```

You should see the `insmod` commands at the top, before the original configuration.

Check for errors in boot messages:

```bash
dmesg | grep -i grub
# Should show no errors
```

## When to Re-apply

Re-apply this fix after:
- Running `grub-mkconfig` (regenerates `/boot/grub/grub.cfg`)
- Kernel updates that trigger config regeneration
- Alpine version upgrades

**Pro tip:** Keep the fix script in `/root/fix-grub.sh` for easy re-application.

## Automated Fix (Future Templates)

If you're creating a new template, the `create-alpine-template.sh` script will automatically apply this fix. The fix is built into the template creation process.

For existing templates or manual installations, use the manual fix above.

## Why the Generic Shim Doesn't Work

The UTM Automation Guide suggests creating `/boot/EFI/BOOT/grub.cfg` as a shim. This works for most distributions but **NOT Alpine** because:

1. Alpine's `BOOTAA64.EFI` has embedded config pointing directly to `/grub/grub.cfg`
2. The shim at `/EFI/BOOT/grub.cfg` is never executed (it's orphaned)
3. Must fix the actual `/boot/grub/grub.cfg` that GRUB loads

Verify what's embedded in BOOTAA64.EFI:

```bash
strings /boot/EFI/BOOT/BOOTAA64.EFI | grep -A3 "configfile"
# Output shows it loads /grub/grub.cfg directly
```

## Troubleshooting

### Fix doesn't persist after reboot

**Cause:** You edited the file but didn't save it properly, or ran `grub-mkconfig` afterward

**Solution:** Re-run the fix script, verify the file content, then reboot

### Still seeing errors after fix

**Cause:** Wrong file edited or modules missing

**Solution:**
```bash
# Verify you edited the right file
ls -l /boot/grub/grub.cfg

# Check if modules exist
ls -l /boot/grub/*/normal.mod
ls -l /boot/grub/*/test.mod

# If modules missing, reinstall GRUB
apk add --reinstall grub grub-efi
grub-install --target=arm64-efi --efi-directory=/boot --removable /dev/vda
# Then re-apply fix
```

### Script fails with "permission denied"

**Cause:** Not running as root

**Solution:**
```bash
# Run as root
sudo /tmp/fix-grub.sh

# Or switch to root
su -
/tmp/fix-grub.sh
```

## Further Reading

For comprehensive GRUB boot flow explanation and Alpine-specific details:
- [Alpine UTM Guide - GRUB Boot Flow](https://gist.github.com/ChristopherA/39b5a9b51dd0ff7eac79da339aa233ee#alpine-grub-boot-flow)
- [UTM Automation Guide - GRUB Bootloader](https://gist.github.com/ChristopherA/96232f85893054b0ac4b4a04d08d8821#grub-bootloader-automation)

For utm-alpine-kit specific documentation:
- [Template Creation](template-creation.md) - Automated template creation includes this fix
- [Troubleshooting](troubleshooting.md) - Other common issues
