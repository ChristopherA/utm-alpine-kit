# Template Creation Guide

Detailed explanation of how Alpine VM template creation works.

## Overview

The `create-alpine-template.sh` script fully automates Alpine Linux installation, turning a 20-minute manual process into a 5-minute hands-off operation.

**What makes this possible:**
1. **Answer files** - Alpine's built-in unattended installation
2. **Serial console automation** - Expect scripts drive interactive prompts
3. **UTM configuration** - PlistBuddy modifies VM settings programmatically
4. **QEMU guest agent** - Enables IP detection and VM control

## Template Creation Process

### High-Level Steps

```
1. Prerequisites Check        → Verify tools, SSH key, ISO exist
2. VM Creation                → Create UTM VM with virtual disk
3. Answer File Prep           → Substitute SSH key, serve via HTTP
4. Serial Console Config      → Configure TcpServer mode for automation
5. VM Boot                    → Boot Alpine ISO
6. Answer File Install        → Run setup-alpine with answer file
7. Disk Installation          → Partition and install to disk
8. First Boot                 → Boot from installed system
9. Password Configuration     → Set root password via SSH
10. ISO Removal               → Delete CD-ROM drive from config
11. Template Ready            → Stopped VM ready for cloning
```

**Total Time:** ~5 minutes

### Detailed Workflow

#### 1. Prerequisites Check

```bash
# Validates:
- UTM installed (/Applications/UTM.app)
- expect available (brew install expect)
- SSH key exists (~/.ssh/id_ed25519_alpine_vm)
- Alpine ISO exists and is readable
- VM name doesn't already exist
```

**Exit Codes:**
- `0` - All checks passed
- `1` - Missing prerequisite

#### 2. VM Creation via utmctl

```bash
utmctl create \
  --name "alpine-template" \
  --memory 512 \
  --cpu 2 \
  --disk-size 4 \
  --cd-image ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso \
  --network bridged
```

Creates:
- 4GB virtual disk (`/dev/vda` inside VM)
- 512MB RAM (adjustable via `--ram`)
- 2 CPU cores (adjustable via `--cpu`)
- Bridged network for internet + SSH access
- CD-ROM with Alpine ISO attached

**Result:** VM bundle at `~/Library/Containers/com.utmapp.UTM/Data/Documents/alpine-template.utm/`

#### 3. Answer File Preparation

The script:

1. **Reads template:** `templates/alpine-template.answers`
2. **Substitutes SSH key:** Replaces `%%SSH_KEY%%` with your public key
3. **Serves via HTTP:** Starts Python HTTP server on port 8888
4. **Makes accessible to VM:** Uses `10.0.2.2:8888` (QEMU user-mode networking)

```bash
# Example answer file snippet
ROOTSSHKEY="ssh-ed25519 AAAAC3Nza... alpine_vm_manager"
HOSTNAMEOPTS="alpine-template"
INTERFACESOPTS="auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp"
```

**Why HTTP instead of file sharing:**
- QEMU user-mode networking provides reliable 10.0.2.2 gateway
- No SMB/NFS complexity
- Works consistently across UTM versions

#### 4. Serial Console Configuration

**Critical step:** Alpine's `setup-alpine` is interactive. We need serial console access to automate it.

```bash
# Configure serial console via PlistBuddy
/usr/libexec/PlistBuddy \
  -c "Add :SerialPort:0:Mode string TcpServer" \
  -c "Add :SerialPort:0:TcpPort integer 4444" \
  config.plist
```

**IMPORTANT:** Case-sensitive! `TcpServer`, not `tcpserver` or `TCP`.

**Why TcpServer mode:**
- Exposes serial console on `localhost:4444`
- Accessible via `nc localhost 4444` or expect scripts
- Bi-directional communication (read + write)
- More reliable than PTY or file modes

**UTM Restart Required:**
UTM caches VM configurations in memory. Must quit and relaunch UTM for changes to take effect.

```bash
osascript -e 'quit app "UTM"'
sleep 3
open -a UTM
sleep 5
```

#### 5. VM Boot from ISO

```bash
utmctl start alpine-template
```

**Boot sequence:**
1. QEMU boots from ISO (CD-ROM has priority over disk)
2. Alpine Linux kernel loads
3. System starts in RAM
4. `setup-alpine` script available at `/sbin/setup-alpine`
5. Serial console active on port 4444

**Detection:** Script waits for `login:` prompt on serial console

#### 6. Answer File Installation

Uses `lib/install-via-answerfile.exp`:

```bash
#!/usr/bin/expect -f
# Connect to serial console
spawn nc localhost 4444

# Login as root (no password on ISO)
expect "login:"
send "root\r"

# Run setup-alpine with answer file
expect "#"
send "setup-alpine -f http://10.0.2.2:8888/alpine-template.answers\r"

# Wait for completion
expect "Installation is complete"
```

**What happens inside VM:**
1. Login as root
2. setup-alpine downloads answer file from 10.0.2.2:8888
3. Processes each line:
   - `KEYMAPOPTS` - Keyboard layout
   - `HOSTNAMEOPTS` - Sets hostname
   - `INTERFACESOPTS` - Network configuration (DHCP on eth0)
   - `TIMEZONEOPTS` - UTC timezone
   - `APKREPOSOPTS` - Fastest mirror
   - `NTPOPTS` - Install chrony for NTP
   - `SSHDOPTS` - Install and enable OpenSSH
   - `ROOTSSHKEY` - Deploy SSH public key
   - `DISKOPTS` - Set disk mode (but doesn't run setup-disk)

**Why DISKOPTS doesn't auto-execute:**
Alpine's answer file quirk. It sets the mode but requires explicit `setup-disk` call.

#### 7. Disk Installation

Uses `lib/install-disk.exp`:

```bash
#!/usr/bin/expect -f
spawn nc localhost 4444

# Run setup-disk in system mode
expect "#"
send "setup-disk -m sys /dev/vda\r"

# Handle prompts
expect "Which disk*"
send "/dev/vda\r"

expect "WARNING:*continue?"
send "y\r"

expect "Enter where to store configs*"
send "none\r"

expect "Enter apk cache directory*"
send "none\r"

# Wait for completion
expect "Installation is complete"
```

**Disk setup creates:**
- Boot partition (FAT32, ~100MB)
- Root partition (ext4, remaining space)
- GRUB bootloader installed
- System files copied from RAM to disk

**Result:** Bootable Alpine installation on /dev/vda

#### 8. First Boot from Disk

```bash
# Reboot via serial console
echo "reboot" | nc localhost 4444

# Wait for shutdown
sleep 10

# Remove ISO from CD-ROM
/usr/libexec/PlistBuddy -c "Delete :Drive:0" config.plist

# Restart UTM to apply change
osascript -e 'quit app "UTM"'
sleep 3
open -a UTM
sleep 5

# Start VM (now boots from disk)
utmctl start alpine-template
```

**Boot sequence:**
1. GRUB loads from /dev/vda
2. Alpine kernel boots
3. System starts from disk
4. sshd and chronyd start automatically
5. QEMU guest agent starts (if installed)

#### 9. Password Configuration

```bash
# Detect IP via QEMU guest agent
VM_IP=$(utmctl ip-address alpine-template | head -1)

# Set password via SSH
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP \
  "echo 'root:alpine' | chpasswd"
```

**Why via SSH:**
- Answer files cannot set passwords directly
- Serial console password setting is unreliable
- SSH with pre-deployed key is most reliable
- Password optional (SSH keys are primary auth)

#### 10. Install QEMU Guest Agent

```bash
# SSH into VM
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP

# Install guest agent
apk add qemu-guest-agent

# Enable and start
rc-update add qemu-guest-agent default
rc-service qemu-guest-agent start
```

**Why guest agent:**
- Enables `utmctl ip-address` command
- Allows graceful shutdown via `utmctl stop`
- Provides VM state information
- Essential for automation

#### 11. Template Finalization

```bash
# Stop VM
utmctl stop alpine-template

# Verify VM bundle exists
ls -lah ~/Library/Containers/com.utmapp.UTM/Data/Documents/alpine-template.utm

# Template ready for cloning
```

**Template contains:**
- Clean Alpine installation (~500MB)
- SSH key deployed for root
- Root password set
- Network configured for DHCP
- sshd, chronyd, qemu-guest-agent enabled
- No additional packages or user data

## Answer File Format

Full specification of Alpine answer file options:

### Required Options

```bash
# Keyboard layout (layout variant)
KEYMAPOPTS="us us"

# Hostname
HOSTNAMEOPTS="alpine-template"

# Network interfaces (shell script format)
INTERFACESOPTS="auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp"

# Timezone (TZ database name or "UTC")
TIMEZONEOPTS="UTC"

# APK repositories (-1 = fastest, -c = CDN, -f = detect)
APKREPOSOPTS="-1"
```

### Optional Options

```bash
# DNS servers (empty = DHCP-provided)
DNSOPTS=""

# HTTP/HTTPS proxy
PROXYOPTS="none"

# NTP daemon (chrony, openntpd, busybox-ntpd)
NTPOPTS="chrony"

# SSH server (openssh, dropbear, none)
SSHDOPTS="openssh"

# Root SSH public key
ROOTSSHKEY="ssh-ed25519 AAAAC3Nza..."

# Disk setup (-m sys = traditional install, -m data = data disk only)
DISKOPTS="-m sys /dev/vda"
```

### Static IP Example

```bash
INTERFACESOPTS="auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1"

DNSOPTS="8.8.8.8 8.8.4.4"
```

## Customizing Templates

### Minimal Template (256MB RAM, 2GB Disk)

```bash
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso \
  --name alpine-minimal \
  --ram 0.25 \
  --cpu 1 \
  --disk 2
```

### Large Template (4GB RAM, 20GB Disk)

```bash
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso \
  --name alpine-large \
  --ram 4 \
  --cpu 4 \
  --disk 20 \
  --password custom_password
```

### Pre-installed Packages

Modify the script to install additional packages after first boot:

```bash
# After password configuration, add:
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<EOF
apk add --no-cache \
  git curl wget \
  python3 py3-pip \
  nodejs npm \
  go rust cargo
EOF
```

**Trade-off:** Larger template size vs faster clone provisioning

## Technical Details

### UTM Configuration (config.plist)

```xml
<key>System</key>
<dict>
    <key>MemorySize</key>
    <integer>512</integer>
    <key>CPUCount</key>
    <integer>2</integer>
</dict>

<key>Network</key>
<array>
    <dict>
        <key>Mode</key>
        <string>Bridged</string>
        <key>MacAddress</key>
        <string>52:54:00:XX:XX:XX</string>
    </dict>
</array>

<key>SerialPort</key>
<array>
    <dict>
        <key>Mode</key>
        <string>TcpServer</string>
        <key>TcpPort</key>
        <integer>4444</integer>
    </dict>
</array>
```

### Serial Console Communication

```bash
# Connect to serial console
nc localhost 4444

# Send commands
echo "ls -la" | nc localhost 4444

# Interactive session
nc localhost 4444
# Type commands, see output in real-time
```

### QEMU Guest Agent Communication

```bash
# Get IP address
utmctl ip-address alpine-template

# Get all network interfaces
utmctl ip-address alpine-template --all

# Graceful shutdown
utmctl stop alpine-template --force=false
```

## Troubleshooting Template Creation

See [troubleshooting.md](troubleshooting.md) for comprehensive solutions.

### Common Issues

**Serial console timeout:**
```bash
# Check if TcpServer is configured
/usr/libexec/PlistBuddy -c "Print :SerialPort:0" config.plist

# Verify UTM was restarted after config change
ps aux | grep UTM
```

**HTTP server fails:**
```bash
# Check if port 8888 is in use
lsof -i :8888

# Kill blocking process
kill $(lsof -t -i :8888)
```

**No IP detected:**
```bash
# Wait longer (up to 30 seconds)
# Or manually find IP
utmctl list
# Note VM name, open UTM console
# In VM: ip addr show eth0
```

**SSH key mismatch:**
```bash
# Verify key exists
ls -la ~/.ssh/id_ed25519_alpine_vm.pub

# Check key was substituted in answer file
curl http://localhost:8888/alpine-template.answers | grep ROOTSSHKEY
```

## Next Steps

- [Clone and use your template](../README.md#daily-workflow-clone--test--destroy)
- [Troubleshoot issues](troubleshooting.md)
- [Try example workflows](../examples/rust-testing.md)
