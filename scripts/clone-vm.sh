#!/bin/bash
#
# clone-vm.sh - Clone Alpine VM Template with Optional Resizing
#
# Usage: ./clone-vm.sh <new-vm-name> [options]
#
# Arguments:
#   new-vm-name     Name for the cloned VM
#
# Options:
#   --template NAME  Template to clone from (default: alpine-template)
#   --ram SIZE       RAM in GB (default: template's value)
#   --cpu COUNT      CPU cores (default: template's value)
#   --ssh FILENAME   Filename of SSH key (default: id_ed25519_alpine_vm)
#   --help           Show this help message
#
# Examples:
#   ./clone-vm.sh test-vm-1
#   ./clone-vm.sh test-vm-2 --template alpine-template --ram 4 --cpu 2
#   ./clone-vm.sh dev-test --ram 8
#
# This script:
# 1. Clones the specified Alpine template
# 2. Optionally resizes RAM and CPU via PlistBuddy
# 3. Generates a new random MAC address
# 4. Starts the VM and detects its IP
# 5. Verifies SSH connectivity
#

set -euo pipefail

# Default configuration
TEMPLATE_NAME="alpine-template"
NEW_VM_NAME=""
NEW_RAM_GB=""
NEW_CPU_COUNT=""
UTM_DOCS="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents"
SSH_KEY_NAME="id_ed25519_alpine_vm"

# Parse arguments
show_help() {
    cat << EOF
Clone Alpine VM Template

Usage: $0 <new-vm-name> [options]

Arguments:
  new-vm-name     Name for the cloned VM

Options:
  --template NAME  Template to clone from (default: alpine-template)
  --ram SIZE       RAM in GB (default: template's value)
  --cpu COUNT      CPU cores (default: template's value)
  --ssh FILENAME   Filename to use for ssh key (default: id_ed25519_alpine_vm)
  --help           Show this help message

Examples:
  $0 test-vm-1
  $0 test-vm-2 --template alpine-template --ram 4 --cpu 2
  $0 dev-test --ram 8

Notes:
  - Template must exist and be stopped
  - New MAC address is automatically generated
  - UTM must restart to apply config changes

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            ;;
        --template)
            TEMPLATE_NAME="$2"
            shift 2
            ;;
        --ram)
            NEW_RAM_GB="$2"
            shift 2
            ;;
        --cpu)
            NEW_CPU_COUNT="$2"
            shift 2
            ;;
        --ssh)
            SSH_KEY_NAME="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$NEW_VM_NAME" ]]; then
                NEW_VM_NAME="$1"
                shift
            else
                echo "Error: Unexpected argument: $1"
                exit 1
            fi
            ;;
    esac
done

# Validate required arguments
if [[ -z "$NEW_VM_NAME" ]]; then
    echo "Error: VM name required"
    echo ""
    show_help
fi

# Header
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Clone Alpine VM Template"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Template:     $TEMPLATE_NAME"
echo "New VM:       $NEW_VM_NAME"
[[ -n "$NEW_RAM_GB" ]] && echo "New RAM:      ${NEW_RAM_GB}GB"
[[ -n "$NEW_CPU_COUNT" ]] && echo "New CPU:      ${NEW_CPU_COUNT} cores"
echo ""

# Check if template exists
if ! utmctl status "$TEMPLATE_NAME" &>/dev/null; then
    echo "Error: Template '$TEMPLATE_NAME' not found"
    echo ""
    echo "Available VMs:"
    utmctl list
    echo ""
    echo "To create the default template:"
    echo "  ./scripts/create-alpine-template.sh \\"
    echo "    --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso"
    exit 1
fi

# Check if new VM name already exists
if utmctl status "$NEW_VM_NAME" &>/dev/null; then
    echo "Error: VM '$NEW_VM_NAME' already exists"
    echo ""
    echo "To delete it:"
    echo "  ./scripts/destroy-vm.sh $NEW_VM_NAME"
    exit 1
fi

# Ensure template is stopped
echo "Checking template status..."
TEMPLATE_STATUS=$(utmctl status "$TEMPLATE_NAME" 2>/dev/null || echo "unknown")
if echo "$TEMPLATE_STATUS" | grep -q "started"; then
    echo "Template is running. Stopping it..."
    utmctl stop "$TEMPLATE_NAME"
    sleep 3
fi

# Clone the VM
echo ""
echo "Cloning VM (10-30 seconds)..."
START_TIME=$(date +%s)

if ! utmctl clone "$TEMPLATE_NAME" --name "$NEW_VM_NAME" 2>&1; then
    echo "Error: Clone failed"
    exit 1
fi

END_TIME=$(date +%s)
CLONE_TIME=$((END_TIME - START_TIME))
echo "Cloned in ${CLONE_TIME}s"

# Path to new VM's config
CONFIG_PLIST="$UTM_DOCS/${NEW_VM_NAME}.utm/config.plist"

# Generate new random MAC address
NEW_MAC=$(printf '52:54:00:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
echo ""
echo "Generating new MAC address: $NEW_MAC"

# Quit UTM to modify config (UTM caches configs in memory)
echo "Quitting UTM to modify configuration..."
osascript -e 'quit app "UTM"' 2>/dev/null || true
sleep 2

# Update MAC address
/usr/libexec/PlistBuddy -c "Set :Network:0:MacAddress $NEW_MAC" "$CONFIG_PLIST" 2>/dev/null || {
    echo "Warning: Could not set MAC address via PlistBuddy"
}

# Update RAM if requested
if [[ -n "$NEW_RAM_GB" ]]; then
    NEW_RAM_MB=$((NEW_RAM_GB * 1024))
    echo "Setting RAM to ${NEW_RAM_GB}GB (${NEW_RAM_MB}MB)..."
    /usr/libexec/PlistBuddy -c "Set :System:MemorySize $NEW_RAM_MB" "$CONFIG_PLIST" 2>/dev/null || {
        echo "Warning: Could not set RAM via PlistBuddy"
    }
fi

# Update CPU if requested
if [[ -n "$NEW_CPU_COUNT" ]]; then
    echo "Setting CPU to ${NEW_CPU_COUNT} cores..."
    /usr/libexec/PlistBuddy -c "Set :System:CPUCount $NEW_CPU_COUNT" "$CONFIG_PLIST" 2>/dev/null || {
        echo "Warning: Could not set CPU count via PlistBuddy"
    }
fi

echo "Configuration updated"

# Restart UTM
echo "Restarting UTM..."
open -a UTM
sleep 3

# Verify VM is registered
if ! utmctl status "$NEW_VM_NAME" &>/dev/null; then
    echo "Error: VM not registered after restart"
    exit 1
fi

# Start the VM
echo ""
echo "Starting VM..."
utmctl start "$NEW_VM_NAME"

echo ""
echo "Waiting for boot and QEMU guest agent..."
sleep 8

# Detect IP address
echo ""
echo "Detecting IP address..."
VM_IP=""
for i in {1..10}; do
    VM_IP=$(utmctl ip-address "$NEW_VM_NAME" 2>/dev/null | head -1 || echo "")
    if [[ -n "$VM_IP" && "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "IP detected: $VM_IP"
        break
    fi
    sleep 2
done

if [[ -z "$VM_IP" || ! "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Could not auto-detect IP address"
    echo ""
    echo "Manual detection:"
    echo "1. Open UTM console for '$NEW_VM_NAME'"
    echo "2. Run: ip addr show eth0 | grep 'inet '"
    echo ""
else
    # Test SSH
    echo ""
    echo "Testing SSH connectivity..."
    if ssh -i ~/.ssh/${SSH_KEY_NAME} -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$VM_IP "echo 'SSH OK'" &>/dev/null; then
        echo "SSH verified"
    else
        echo "Warning: SSH not responding (may need more time)"
    fi
fi

# Success summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VM '$NEW_VM_NAME' is ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [[ -n "$VM_IP" ]]; then
    echo "IP Address: $VM_IP"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  SSH into VM:"
    echo "    ssh -i ~/.ssh/$SSH_KEY_NAME root@$VM_IP"
    echo ""
    echo "  Update and test:"
    echo "    ssh -i ~/.ssh/$SSH_KEY_NAME root@$VM_IP 'apk update && apk upgrade'"
    echo ""
    echo "  Destroy when done:"
    echo "    ./scripts/destroy-vm.sh $NEW_VM_NAME"
    echo ""
fi
