#!/bin/bash
#
# list-templates.sh - List Available Alpine VM Templates
#
# Usage: ./list-templates.sh [options]
#
# Options:
#   --verbose     Show detailed VM information
#   --help        Show this help message
#
# Examples:
#   ./list-templates.sh
#   ./list-templates.sh --verbose
#
# This script lists all VMs available in UTM, highlighting
# those that appear to be templates (typically named *-template).
#

set -euo pipefail

VERBOSE=false

# Show help
show_help() {
    cat << EOF
List Available Alpine VM Templates

Usage: $0 [options]

Options:
  --verbose     Show detailed VM information
  --help        Show this help message

Examples:
  $0
  $0 --verbose

This script lists all VMs in UTM, with templates highlighted.

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Header
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Alpine VM Manager - Available VMs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get list of VMs
VM_LIST=$(utmctl list 2>/dev/null || echo "")

if [[ -z "$VM_LIST" ]]; then
    echo "No VMs found in UTM"
    echo ""
    echo "To create the default Alpine template:"
    echo "  ./scripts/create-alpine-template.sh \\"
    echo "    --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso"
    echo ""
    exit 0
fi

# Parse and display VMs
echo "Available VMs:"
echo ""

TEMPLATES_FOUND=false
INSTANCES_FOUND=false

while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Check if it's a template (contains "-template")
    if [[ "$line" == *"-template"* ]] || [[ "$line" == *"template"* ]]; then
        if [[ "$TEMPLATES_FOUND" = "false" ]]; then
            echo "Templates:"
            TEMPLATES_FOUND=true
        fi
        echo "  • $line"

        if [[ "$VERBOSE" = "true" ]]; then
            VM_NAME=$(echo "$line" | awk '{print $1}')
            VM_STATUS=$(utmctl status "$VM_NAME" 2>/dev/null || echo "unknown")
            echo "    Status: $VM_STATUS"

            # Try to get IP if running
            if echo "$VM_STATUS" | grep -q "started"; then
                VM_IP=$(utmctl ip-address "$VM_NAME" 2>/dev/null | head -1 || echo "detecting...")
                echo "    IP: $VM_IP"
            fi
            echo ""
        fi
    fi
done <<< "$VM_LIST"

# Show non-template VMs
if [[ "$TEMPLATES_FOUND" = "true" ]]; then
    echo ""
    echo "Active VMs:"
fi

while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Show non-templates
    if [[ "$line" != *"-template"* ]] && [[ "$line" != *"template"* ]]; then
        INSTANCES_FOUND=true
        echo "  • $line"

        if [[ "$VERBOSE" = "true" ]]; then
            VM_NAME=$(echo "$line" | awk '{print $1}')
            VM_STATUS=$(utmctl status "$VM_NAME" 2>/dev/null || echo "unknown")
            echo "    Status: $VM_STATUS"

            if echo "$VM_STATUS" | grep -q "started"; then
                VM_IP=$(utmctl ip-address "$VM_NAME" 2>/dev/null | head -1 || echo "detecting...")
                echo "    IP: $VM_IP"
            fi
            echo ""
        fi
    fi
done <<< "$VM_LIST"

if [[ "$INSTANCES_FOUND" = "false" && "$TEMPLATES_FOUND" = "true" ]]; then
    echo "  (none)"
fi

# Usage hints
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To clone a template:"
echo "  ./scripts/clone-vm.sh <new-name> --template alpine-template"
echo ""
echo "To create a new template:"
echo "  ./scripts/create-alpine-template.sh --iso <path-to-iso>"
echo ""
