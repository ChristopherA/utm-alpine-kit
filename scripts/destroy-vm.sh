#!/bin/bash
#
# destroy-vm.sh - Destroy Alpine VM and Clean Up
#
# Usage: ./destroy-vm.sh <vm-name> [options]
#
# Arguments:
#   vm-name         Name of the VM to destroy
#
# Options:
#   --yes           Skip confirmation prompt
#   --help          Show this help message
#
# Examples:
#   ./destroy-vm.sh test-vm-1
#   ./destroy-vm.sh test-vm-2 --yes
#
# This script:
# 1. Stops the running VM
# 2. Deletes the VM bundle from disk
# 3. Cleans up SSH known_hosts entries
# 4. Reports disk space freed
#

set -euo pipefail

# Configuration
UTM_DOCS_DIR="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents"
VM_NAME=""
SKIP_CONFIRM=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help
show_help() {
    cat << EOF
Destroy Alpine VM and Clean Up

Usage: $0 <vm-name> [options]

Arguments:
  vm-name         Name of the VM to destroy

Options:
  --yes           Skip confirmation prompt
  --help          Show this help message

Examples:
  $0 test-vm-1
  $0 test-vm-2 --yes

This script stops the VM, deletes all files, and cleans up
SSH known_hosts entries.

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            ;;
        --yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$VM_NAME" ]]; then
                VM_NAME="$1"
                shift
            else
                echo "Error: Unexpected argument: $1"
                exit 1
            fi
            ;;
    esac
done

# Validate arguments
if [[ -z "$VM_NAME" ]]; then
    echo "Error: VM name required"
    echo ""
    show_help
fi

# Header
echo ""
log_warn "VM Destruction: $VM_NAME"
echo ""

# Confirm destruction
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    log_warn "This will permanently delete the VM: $VM_NAME"
    echo -n "Are you sure? (yes/no): "
    read -r CONFIRM
    echo ""

    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi
fi

# Check if VM exists
log_info "Checking if VM exists..."
VM_EXISTS=false
if utmctl status "$VM_NAME" &>/dev/null; then
    VM_EXISTS=true
    log_info "VM found: $VM_NAME"
else
    log_warn "VM not found via utmctl"
fi

# Calculate disk space
VM_BUNDLE="$UTM_DOCS_DIR/${VM_NAME}.utm"
if [[ -d "$VM_BUNDLE" ]]; then
    DISK_USAGE=$(du -sh "$VM_BUNDLE" 2>/dev/null | awk '{print $1}')
    log_info "Disk space to be freed: $DISK_USAGE"
else
    if [[ "$VM_EXISTS" = "false" ]]; then
        log_error "VM not found in UTM or on disk"
        exit 1
    fi
fi

# Stop VM if running
if [[ "$VM_EXISTS" = "true" ]]; then
    log_info "Checking VM status..."
    VM_STATUS=$(utmctl status "$VM_NAME" 2>/dev/null || echo "unknown")

    if echo "$VM_STATUS" | grep -q "started"; then
        log_info "Stopping VM..."
        utmctl stop "$VM_NAME" || log_warn "Failed to stop VM via utmctl"
        sleep 2
    else
        log_info "VM not running"
    fi
fi

# Delete VM
log_info "Deleting VM..."

if [[ "$VM_EXISTS" = "true" ]]; then
    # Try utmctl delete first
    if utmctl delete "$VM_NAME" 2>/dev/null; then
        log_info "VM deleted via utmctl"
    else
        log_warn "utmctl delete failed, deleting bundle directly"
        if [[ -d "$VM_BUNDLE" ]]; then
            rm -rf "$VM_BUNDLE"
            log_info "VM bundle deleted"
        fi
    fi
else
    # Direct deletion
    if [[ -d "$VM_BUNDLE" ]]; then
        rm -rf "$VM_BUNDLE"
        log_info "VM bundle deleted"
    fi
fi

# Get IP address for SSH cleanup
VM_IP=""
if [[ "$VM_EXISTS" = "true" ]]; then
    # Try to get IP from QEMU guest agent before deletion
    VM_IP=$(utmctl ip-address "$VM_NAME" 2>/dev/null | head -1 || echo "")
fi

# Clean SSH known_hosts
if [[ -n "$VM_IP" && "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_info "Cleaning SSH known_hosts for IP: $VM_IP"
    ssh-keygen -R "$VM_IP" 2>/dev/null || true
else
    log_warn "No IP detected, skipping SSH cleanup"
    log_info "You may need to manually clean ~/.ssh/known_hosts"
fi

# Success summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VM Destruction Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "VM Name: $VM_NAME"
if [[ -n "$VM_IP" ]]; then
    echo "VM IP:   $VM_IP (cleaned from known_hosts)"
fi
if [[ -n "$DISK_USAGE" ]]; then
    echo "Freed:   $DISK_USAGE"
fi
echo ""
echo "To create a new VM:"
echo "  ./scripts/clone-vm.sh <new-name>"
echo ""
