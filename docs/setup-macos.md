# macOS Setup Guide

Complete setup instructions for Alpine VM Manager on macOS with Apple Silicon.

## Prerequisites

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1, M2, M3, M4)
- 8GB RAM minimum (16GB recommended)
- 20GB free disk space
- Administrator access

## Step 1: Install UTM

UTM is a full-featured virtual machine host for macOS based on QEMU.

### Download and Install

**Option A: Direct Download (Recommended)**
```bash
# Download from official website
open https://mac.getutm.app/

# Or via GitHub releases
open https://github.com/utmapp/UTM/releases
```

Download the `.dmg` file, open it, and drag UTM to Applications.

**Option B: Mac App Store**
```bash
# Open Mac App Store to UTM page
open https://apps.apple.com/app/utm-virtual-machines/id1538878817
```

**Note:** App Store version costs $9.99 to support development. Functionally identical to free version.

### Verify Installation

```bash
# Check UTM is installed
ls -la /Applications/UTM.app

# Check utmctl is available
/Applications/UTM.app/Contents/MacOS/utmctl --help

# Create symlink for convenience
sudo ln -sf /Applications/UTM.app/Contents/MacOS/utmctl /usr/local/bin/utmctl

# Verify symlink
utmctl --help
```

### Launch UTM Once

```bash
# Open UTM for the first time
open -a UTM
```

This initializes UTM's container directory at:
```
~/Library/Containers/com.utmapp.UTM/Data/Documents/
```

You can quit UTM after it opens successfully.

## Step 2: Install Required Tools

### Install Homebrew (if not already installed)

```bash
# Check if Homebrew is installed
which brew

# If not installed, install it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Follow post-install instructions to add to PATH
# For Apple Silicon:
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Install expect

Required for serial console automation:

```bash
brew install expect

# Verify installation
expect -v
# Should output: expect version 5.45.x
```

## Step 3: Generate SSH Key

Create a dedicated SSH key for Alpine VM access:

```bash
# Generate ED25519 key (modern, secure)
ssh-keygen -t ed25519 \
  -f ~/.ssh/id_ed25519_alpine_vm \
  -C "alpine_vm_manager"

# When prompted:
# - Enter passphrase: (optional, press Enter for none)
# - Confirm passphrase: (press Enter again if no passphrase)

# Verify keys created
ls -la ~/.ssh/id_ed25519_alpine_vm*
# Should show:
#   id_ed25519_alpine_vm       (private key)
#   id_ed25519_alpine_vm.pub   (public key)

# View public key (for reference)
cat ~/.ssh/id_ed25519_alpine_vm.pub
```

**Security Note:** These keys are used only for local VM access. If you set a passphrase, you'll need to enter it for each VM connection.

## Step 4: Download Alpine ISO

Download the Alpine Linux virtual image for ARM64:

```bash
# Create cache directory
mkdir -p ~/.cache/vms

# Download Alpine 3.22 virtual ISO (ARM64)
cd ~/.cache/vms
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-virt-3.22.0-aarch64.iso

# Verify download
ls -lh alpine-virt-3.22.0-aarch64.iso
# Should be ~50MB

# Optional: Verify checksum
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-virt-3.22.0-aarch64.iso.sha256
shasum -a 256 -c alpine-virt-3.22.0-aarch64.iso.sha256
# Should output: alpine-virt-3.22.0-aarch64.iso: OK
```

**Why `virt` image?**
- Optimized for virtualization
- Includes virtio drivers
- Minimal size (~50MB)
- QEMU guest agent compatible

**Alternative versions:**
- Latest version: Check [Alpine Downloads](https://alpinelinux.org/downloads/)
- Other architectures: Not compatible with Apple Silicon Macs

## Step 5: Clone Repository

```bash
# Navigate to your preferred location
cd ~/Documents  # or wherever you keep projects

# Clone repository
git clone https://github.com/ChristopherA/utm-alpine-kit.git

# Enter directory
cd utm-alpine-kit

# Verify scripts are present
ls -la scripts/
# Should show:
#   create-alpine-template.sh
#   clone-vm.sh
#   destroy-vm.sh
#   provision-for-testing.sh
#   list-templates.sh
#   lib/
```

## Step 6: Create Alpine Template

Create your first Alpine VM template:

```bash
# Ensure you're in the repository directory
cd ~/Documents/utm-alpine-kit  # adjust path if different

# Run template creation script
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso

# This takes ~5 minutes
# You'll see progress for:
# 1. Prerequisites check
# 2. VM creation
# 3. Answer file preparation
# 4. Serial console configuration
# 5. Alpine installation
# 6. Disk setup
# 7. First boot
# 8. Password configuration
# 9. Template verification
```

### Expected Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Alpine Template Creation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Template: alpine-template
ISO: ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso
RAM: 512MB
CPU: 2 cores
Disk: 4GB

[... installation progress ...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Alpine template 'alpine-template' created successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Template IP: 192.168.1.xxx
Template is stopped and ready for cloning

Next steps:
  ./scripts/clone-vm.sh test-vm-1
  ./scripts/clone-vm.sh test-vm-2 --ram 4 --cpu 2
```

### Troubleshooting Template Creation

If creation fails, see [troubleshooting.md](troubleshooting.md) for detailed solutions.

Common issues:
- **HTTP server fails to start:** Port 8888 already in use
- **Serial console timeout:** UTM not restarted after config change
- **No IP detected:** Wait longer for QEMU guest agent

## Step 7: Verify Setup

Test that everything works:

```bash
# List VMs (should show alpine-template)
utmctl list

# Clone template
./scripts/clone-vm.sh test-setup

# Should output IP address after ~20 seconds
# Example: 192.168.1.100

# Test SSH access
ssh -i ~/.ssh/id_ed25519_alpine_vm root@192.168.1.100

# Inside VM, verify:
cat /etc/os-release
# Should show Alpine Linux 3.22

# Check services
rc-status
# Should show sshd, chronyd, qemu-guest-agent running

# Exit VM
exit

# Destroy test VM
./scripts/destroy-vm.sh test-setup --yes
```

## Step 8: Optional Configuration

### Set Default Password (Optional)

The template uses SSH keys by default. To set a default password:

```bash
# Start template
utmctl start alpine-template

# Wait for boot
sleep 10

# Get IP
TEMPLATE_IP=$(utmctl ip-address alpine-template | head -1)

# Set password via SSH
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$TEMPLATE_IP \
  "echo 'root:YourPassword' | chpasswd"

# Stop template
utmctl stop alpine-template
```

### Create Additional Templates (Optional)

Create specialized templates for different scenarios:

```bash
# Minimal template (256MB RAM, 1 CPU, 2GB disk)
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso \
  --name alpine-minimal \
  --ram 0.25 \
  --cpu 1 \
  --disk 2

# Large template (2GB RAM, 4 CPUs, 10GB disk)
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso \
  --name alpine-large \
  --ram 2 \
  --cpu 4 \
  --disk 10
```

### Shell Aliases (Optional)

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Alpine VM Manager aliases
alias alpine-create='~/Documents/utm-alpine-kit/scripts/create-alpine-template.sh'
alias alpine-clone='~/Documents/utm-alpine-kit/scripts/clone-vm.sh'
alias alpine-test='~/Documents/utm-alpine-kit/scripts/provision-for-testing.sh'
alias alpine-destroy='~/Documents/utm-alpine-kit/scripts/destroy-vm.sh'
alias alpine-list='~/Documents/utm-alpine-kit/scripts/list-templates.sh'

# Reload shell
source ~/.zshrc  # or ~/.bashrc
```

Then use:
```bash
alpine-clone my-test
alpine-test my-test 192.168.1.100 https://github.com/user/repo.git
alpine-destroy my-test --yes
```

## Setup Complete!

You're ready to use Alpine VM Manager for rapid testing workflows.

### Next Steps

1. **Read the main README:** [../README.md](../README.md)
2. **Try example workflows:** [../examples/rust-testing.md](../examples/rust-testing.md)
3. **Learn about templates:** [template-creation.md](template-creation.md)

### Quick Reference

```bash
# Create template (one-time)
./scripts/create-alpine-template.sh --iso ~/.cache/vms/alpine-virt-*.iso

# Daily workflow
./scripts/clone-vm.sh test-vm-1
./scripts/provision-for-testing.sh test-vm-1 <IP> <repo-url>
./scripts/destroy-vm.sh test-vm-1 --yes

# List all VMs
./scripts/list-templates.sh

# SSH into any VM
ssh -i ~/.ssh/id_ed25519_alpine_vm root@<IP>
```

## Updating

```bash
# Update repository
cd ~/Documents/utm-alpine-kit
git pull

# Update Alpine ISO (when new version available)
cd ~/.cache/vms
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-virt-3.22.0-aarch64.iso

# Recreate template with new version
./scripts/create-alpine-template.sh --iso ~/.cache/vms/alpine-virt-*.iso
```

## Uninstalling

```bash
# Delete all VMs
for vm in $(utmctl list | awk '{print $1}'); do
  utmctl stop "$vm"
  utmctl delete "$vm"
done

# Remove repository
rm -rf ~/Documents/utm-alpine-kit

# Remove ISO cache
rm -rf ~/.cache/vms

# Remove SSH key (optional)
rm ~/.ssh/id_ed25519_alpine_vm*

# Uninstall UTM (if desired)
# Just delete /Applications/UTM.app
```

## Support

- **Issues:** Report at [GitHub Issues](https://github.com/ChristopherA/utm-alpine-kit/issues)
- **Questions:** Ask in [GitHub Discussions](https://github.com/ChristopherA/utm-alpine-kit/discussions)
