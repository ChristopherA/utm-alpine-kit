#!/bin/bash
#
# create-alpine-template.sh
# Automated Alpine Linux template creation for UTM
#
# This script creates a ready-to-clone Alpine Linux template VM using:
# - Answer file for unattended installation
# - Serial console (TcpServer) for automation
# - Expect scripts for interactive prompts
#
# Usage: ./create-alpine-template.sh [OPTIONS]
#
# Options:
#   --iso PATH       Path to Alpine virt ISO (required)
#   --ram GB         RAM size in GB (default: 2)
#   --cpu N          CPU cores (default: 2)
#   --disk GB        Disk size in GB (default: 20)
#   --password PWD   Root password (default: LifeWithAlacrity)
#   --network MODE   Network mode (default: bridged)
#   --help           Show this help
#
# Requirements:
#   - UTM installed (/Applications/UTM.app)
#   - expect command available
#   - SSH key at ~/.ssh/id_ed25519_alpine_vm.pub
#   - Answer file at ../templates/alpine-template.answers
#
# Duration: ~5 minutes
#
# Exit codes:
#   0 - Template created successfully
#   1 - Prerequisites missing or validation failed
#   2 - Installation failed
#

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
TEMPLATES_DIR="$(cd "${SCRIPT_DIR}/../templates" && pwd)"
ANSWER_FILE="${TEMPLATES_DIR}/alpine-template.answers"

# Default values
VM_NAME="alpine-template"
RAM_GB=2
CPU_COUNT=2
DISK_GB=20
ROOT_PASSWORD="LifeWithAlacrity2025"
ISO_PATH=""
NETWORK_MODE="bridged"
SERIAL_PORT=4444
HTTP_PORT=8888

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}==>${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

log_step() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$*${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Cleanup function
cleanup() {
    local exit_code=$?

    log_info "Cleaning up..."

    # Stop HTTP server if running
    if [ -n "${HTTP_SERVER_PID:-}" ]; then
        kill "${HTTP_SERVER_PID}" 2>/dev/null || true
        log_info "HTTP server stopped (PID: $HTTP_SERVER_PID)"
    fi

    # Also kill any Python HTTP servers on port 8888 (in case of leftover)
    local port_pid
    port_pid=$(lsof -ti :${HTTP_PORT} 2>/dev/null || true)
    if [ -n "$port_pid" ]; then
        kill "$port_pid" 2>/dev/null || true
        log_info "Killed HTTP server on port $HTTP_PORT (PID: $port_pid)"
    fi

    # Remove temp answer file
    rm -f /tmp/alpine-answer.txt

    if [ $exit_code -ne 0 ]; then
        log_error "Template creation failed with exit code $exit_code"
        log_info "VM may be in incomplete state: $VM_NAME"
        log_info "You may need to delete it manually: utmctl delete $VM_NAME"
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --iso)
                ISO_PATH="$2"
                shift 2
                ;;
            --ram)
                RAM_GB="$2"
                shift 2
                ;;
            --cpu)
                CPU_COUNT="$2"
                shift 2
                ;;
            --disk)
                DISK_GB="$2"
                shift 2
                ;;
            --password)
                ROOT_PASSWORD="$2"
                shift 2
                ;;
            --network)
                NETWORK_MODE="$2"
                shift 2
                ;;
            --help)
                grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# \?//'
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating Prerequisites"

    local errors=0

    # Check UTM
    if [ ! -d "/Applications/UTM.app" ]; then
        log_error "UTM not found at /Applications/UTM.app"
        log_info "Install from: https://mac.getutm.app/"
        ((errors++))
    else
        log_info "✓ UTM installed"
    fi

    # Check utmctl
    if ! command -v utmctl &>/dev/null; then
        log_warn "utmctl not in PATH"
        log_info "Creating alias: utmctl=/Applications/UTM.app/Contents/MacOS/utmctl"
        alias utmctl="/Applications/UTM.app/Contents/MacOS/utmctl"
    else
        log_info "✓ utmctl available"
    fi

    # Check expect
    if ! command -v expect &>/dev/null; then
        log_error "expect not found"
        log_info "Install with: brew install expect"
        ((errors++))
    else
        log_info "✓ expect installed"
    fi

    # Check ISO
    if [ -z "$ISO_PATH" ]; then
        log_error "ISO path required (--iso option)"
        ((errors++))
    elif [ ! -f "$ISO_PATH" ]; then
        log_error "ISO not found: $ISO_PATH"
        ((errors++))
    else
        log_info "✓ Alpine ISO: $ISO_PATH"
    fi

    # Check SSH key
    if [ ! -f ~/.ssh/id_ed25519_alpine_vm.pub ]; then
        log_error "SSH public key not found: ~/.ssh/id_ed25519_alpine_vm.pub"
        log_info "Generate with: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_alpine_vm"
        ((errors++))
    else
        log_info "✓ SSH key found"
    fi

    # Check answer file template
    if [ ! -f "$ANSWER_FILE" ]; then
        log_error "Answer file template not found: $ANSWER_FILE"
        ((errors++))
    else
        log_info "✓ Answer file template: $ANSWER_FILE"
    fi

    # Check library scripts
    if [ ! -f "${LIB_DIR}/install-via-answerfile.exp" ]; then
        log_error "Missing: install-via-answerfile.exp"
        ((errors++))
    fi
    if [ ! -f "${LIB_DIR}/install-disk.exp" ]; then
        log_error "Missing: install-disk.exp"
        ((errors++))
    fi
    if [ $errors -eq 0 ]; then
        log_info "✓ Library scripts present"
    fi

    if [ $errors -gt 0 ]; then
        log_error "Prerequisites validation failed ($errors errors)"
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

# Prepare answer file with SSH key
prepare_answer_file() {
    log_step "Preparing Answer File"

    local ssh_key
    ssh_key=$(cat ~/.ssh/id_ed25519_alpine_vm.pub)

    # Copy template and substitute SSH key
    sed "s|%%SSH_KEY%%|${ssh_key}|" "$ANSWER_FILE" > /tmp/alpine-answer.txt

    log_info "Answer file prepared at /tmp/alpine-answer.txt"
}

# Get host IP for answer file server
get_host_ip() {
    local ip
    # Try en0 first (Ethernet/WiFi), then en1
    ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")

    if [ -z "$ip" ]; then
        log_error "Could not determine host IP address"
        log_info "Check network connectivity"
        exit 1
    fi

    echo "$ip"
}

# Start HTTP server for answer file
start_http_server() {
    log_step "Starting HTTP Server"

    # Kill any existing server on port (cleanup from previous runs)
    local existing_pid
    existing_pid=$(lsof -ti :${HTTP_PORT} 2>/dev/null || true)
    if [ -n "$existing_pid" ]; then
        log_warn "Killing existing HTTP server on port $HTTP_PORT (PID: $existing_pid)"
        kill "$existing_pid" 2>/dev/null || true
        sleep 1
    fi

    local host_ip
    host_ip=$(get_host_ip)

    log_info "Host IP: $host_ip"
    log_info "Serving /tmp on port $HTTP_PORT"

    # Start Python HTTP server in background
    cd /tmp
    python3 -m http.server $HTTP_PORT > /dev/null 2>&1 &
    HTTP_SERVER_PID=$!

    sleep 2

    # Verify server is running
    if ! kill -0 $HTTP_SERVER_PID 2>/dev/null; then
        log_error "HTTP server failed to start"
        exit 1
    fi

    log_info "✓ HTTP server running (PID: $HTTP_SERVER_PID)"
    log_info "Answer file URL: http://${host_ip}:${HTTP_PORT}/alpine-answer.txt"

    echo "$host_ip"
}

# Create VM via UTM
create_vm() {
    log_step "Creating VM: $VM_NAME"

    # Check if VM already exists
    if utmctl list 2>/dev/null | grep -q "$VM_NAME"; then
        log_warn "VM '$VM_NAME' already exists"
        read -p "Delete and recreate? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing VM..."
            utmctl stop "$VM_NAME" 2>/dev/null || true
            sleep 2
            utmctl delete "$VM_NAME"
            sleep 2
        else
            log_error "Aborted by user"
            exit 1
        fi
    fi

    log_info "Creating VM via AppleScript..."
    log_info "  RAM: ${RAM_GB}GB ($(( RAM_GB * 1024 ))MB)"
    log_info "  CPU: ${CPU_COUNT} cores"
    log_info "  Disk: ${DISK_GB}GB ($(( DISK_GB * 1024 ))MB)"

    # Ensure UTM is running
    if ! pgrep -x "UTM" > /dev/null; then
        log_info "Starting UTM..."
        open -a UTM
        sleep 3
    fi

    # Create VM using AppleScript (utmctl doesn't have create command)
    osascript <<EOF
tell application "UTM"
    set iso to POSIX file "$ISO_PATH"
    set vm to make new virtual machine with properties {backend:qemu, configuration:{name:"$VM_NAME", architecture:"aarch64", memory:$(( RAM_GB * 1024 )), cpu cores:$CPU_COUNT, drives:{{removable:true, source:iso}, {guest size:$(( DISK_GB * 1024 ))}}, network interfaces:{{mode:$NETWORK_MODE}}, displays:{{hardware:"virtio-gpu-gl-pci"}}}}
    return name of vm
end tell
EOF

    if [ $? -ne 0 ]; then
        log_error "Failed to create VM via AppleScript"
        exit 1
    fi

    log_info "✓ VM created: $VM_NAME"
}

# Configure serial console via PlistBuddy
configure_serial_console() {
    log_step "Configuring Serial Console"

    local vm_path=~/"Library/Containers/com.utmapp.UTM/Data/Documents/${VM_NAME}.utm"
    local config_plist="${vm_path}/config.plist"

    if [ ! -f "$config_plist" ]; then
        log_error "Config not found: $config_plist"
        exit 1
    fi

    log_info "Configuring TcpServer serial console..."

    # Set serial console mode (CRITICAL: case-sensitive "TcpServer")
    /usr/libexec/PlistBuddy -c "Add :Serial array" "$config_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :Serial:0 dict" "$config_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :Serial:0:Mode TcpServer" "$config_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :Serial:0:Mode string TcpServer" "$config_plist"
    /usr/libexec/PlistBuddy -c "Add :Serial:0:Target string Auto" "$config_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :Serial:0:TcpPort integer $SERIAL_PORT" "$config_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :Serial:0:TcpPort $SERIAL_PORT" "$config_plist"

    log_info "✓ Serial console configured on port $SERIAL_PORT"
    log_info "  Mode: TcpServer (case-sensitive!)"
    log_info "  Port: $SERIAL_PORT"
}

# Main execution
parse_args "$@"

log_info "Alpine Linux Template Creation"
log_info "Template name: $VM_NAME"

validate_prerequisites
prepare_answer_file

HOST_IP=$(start_http_server)
ANSWER_URL="http://${HOST_IP}:${HTTP_PORT}/alpine-answer.txt"

create_vm
configure_serial_console

# CRITICAL: Restart UTM to apply serial console configuration
# UTM caches VM configs in memory - changes don't apply until restart
log_info "Restarting UTM to apply serial console configuration..."
osascript -e 'quit app "UTM"' 2>/dev/null || pkill -x UTM || true
sleep 3
open -a UTM
sleep 5

log_step "Starting VM and Installation"
log_info "Starting $VM_NAME..."
utmctl start "$VM_NAME"

log_info "Waiting for VM to boot from ISO (15 seconds)..."
sleep 15

log_info "Running Alpine installation (answer file + disk + qemu-guest-agent)..."
# Export SSH key for expect script to use
export SSH_KEY="$(cat ~/.ssh/id_ed25519_alpine_vm.pub)"
if ! "${LIB_DIR}/install-via-answerfile.exp"; then
    log_error "Alpine installation failed"
    exit 2
fi

log_info "Installation complete!"
sleep 5

log_step "Post-Installation Configuration"

log_info "Stopping VM..."
utmctl stop "$VM_NAME"
sleep 3

log_info "Removing ISO from configuration..."
# The VM has CD-ROM as Drive:0, need to delete it
VM_PATH=~/"Library/Containers/com.utmapp.UTM/Data/Documents/${VM_NAME}.utm"
/usr/libexec/PlistBuddy -c "Delete :Drive:0" "${VM_PATH}/config.plist"

log_warn "Restarting UTM to reload configuration..."
log_info "This is required for config changes to take effect"
osascript -e 'quit app "UTM"' 2>/dev/null || pkill -x UTM || true
sleep 3
open -a UTM
sleep 5

log_info "Starting VM from installed disk..."
utmctl start "$VM_NAME"

log_info "Waiting for boot from disk and services to start (30 seconds)..."
sleep 30

log_info "Getting VM IP address..."
VM_IP=$(utmctl ip-address "$VM_NAME" 2>/dev/null | head -1 || echo "")

if [ -z "$VM_IP" ]; then
    log_warn "Could not get IP via qemu-guest-agent"
    log_info "Trying to find IP via network scan..."
    # This is a fallback, may not always work
    VM_IP=""
fi

if [ -n "$VM_IP" ]; then
    log_info "VM IP: $VM_IP"

    log_info "Setting root password via SSH..."
    sleep 5

    # Password is already set by expect script during installation
    log_info "✓ Password set: $ROOT_PASSWORD"

    # Add SSH key via password authentication (with retries)
    # Use file redirection instead of piping to avoid subshell variable issues
    log_info "Adding SSH public key..."
    MAX_RETRIES=5
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Try to add the key (using < instead of | to avoid subshell)
        if sshpass -p "$ROOT_PASSWORD" \
            ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 \
            root@"${VM_IP}" \
            "cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && sync" \
            < ~/.ssh/id_ed25519_alpine_vm.pub; then

            # Verify the key was actually added
            if sshpass -p "$ROOT_PASSWORD" \
                ssh \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=5 \
                root@"${VM_IP}" \
                "test -f /root/.ssh/authorized_keys && test -s /root/.ssh/authorized_keys"; then
                log_info "✓ SSH key added successfully"
                break
            else
                log_warn "Key add command succeeded but file verification failed"
            fi
        else
            log_warn "SSH key add command failed (attempt $((RETRY_COUNT + 1)))"
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log_warn "Retry $RETRY_COUNT/$MAX_RETRIES: Waiting for SSH to be ready..."
            sleep 5
        else
            log_warn "Could not add SSH key after $MAX_RETRIES attempts"
            log_info "Template created with password-only authentication"
        fi
    done
else
    log_warn "Could not determine VM IP"
    log_info "You may need to set password manually via serial console"
fi

log_info "Stopping template VM..."
utmctl stop "$VM_NAME"

log_step "Template Creation Complete!"
echo ""
log_info "Template: $VM_NAME"
log_info "Location: ~/Library/Containers/com.utmapp.UTM/Data/Documents/${VM_NAME}.utm"
log_info "Password: $ROOT_PASSWORD"
log_info "SSH Key: ~/.ssh/id_ed25519_alpine_vm"
echo ""
log_info "Next steps:"
log_info "  1. Test: utmctl start $VM_NAME"
log_info "  2. Clone: ./clone-vm.sh my-test-vm"
log_info "  3. Use: ssh root@\$(utmctl ip-address my-test-vm)"
echo ""
