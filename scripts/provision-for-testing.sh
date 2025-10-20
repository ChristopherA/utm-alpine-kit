#!/bin/bash
#
# provision-for-testing.sh - Provision Alpine VM for Testing
#
# Usage: ./provision-for-testing.sh <vm-name> <vm-ip> [repo-url] [test-command]
#
# Arguments:
#   vm-name         Name of the VM
#   vm-ip           IP address of the VM
#   repo-url        Optional GitHub repository URL to test
#   test-command    Optional test command (default: "make test")
#
# Examples:
#   ./provision-for-testing.sh test-vm-1 192.168.1.100
#   ./provision-for-testing.sh test-vm-1 192.168.1.100 https://github.com/user/repo.git
#   ./provision-for-testing.sh test-vm-1 192.168.1.100 https://github.com/user/repo.git "npm test"
#
# This script:
# 1. Updates system packages
# 2. Installs essential dependencies
# 3. Clones repository (if provided)
# 4. Auto-detects language and installs dependencies
# 5. Runs tests (if repo provided)
# 6. Saves results locally
#

set -euo pipefail

# Configuration
SSH_KEY="$HOME/.ssh/id_ed25519_alpine_vm"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
WORK_DIR="/root/testing"
RESULTS_DIR="./results/$(date +%Y%m%d-%H%M%S)"

# Arguments
VM_NAME="${1:-}"
VM_IP="${2:-}"
REPO_URL="${3:-}"
TEST_COMMAND="${4:-make test}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Validate arguments
if [[ -z "$VM_NAME" ]] || [[ -z "$VM_IP" ]]; then
    log_error "VM name and IP required"
    echo "Usage: $0 <vm-name> <vm-ip> [repo-url] [test-command]"
    echo ""
    echo "Examples:"
    echo "  $0 test-vm-1 192.168.1.100"
    echo "  $0 test-vm-1 192.168.1.100 https://github.com/user/repo.git"
    echo "  $0 test-vm-1 192.168.1.100 https://github.com/user/repo.git 'npm test'"
    exit 1
fi

PROVISION_ONLY=false
if [[ -z "$REPO_URL" ]]; then
    log_warn "No repository URL - will only update system"
    PROVISION_ONLY=true
fi

# Header
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Provision Alpine VM for Testing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "VM: $VM_NAME ($VM_IP)"
[[ -n "$REPO_URL" ]] && echo "Repo: $REPO_URL"
[[ -n "$REPO_URL" ]] && echo "Test: $TEST_COMMAND"
echo ""

# Test SSH connectivity
log_step "Testing SSH connectivity..."
if ! ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" exit 2>/dev/null; then
    log_error "Cannot connect via SSH"
    log_error "Check VM is running: utmctl status $VM_NAME"
    exit 1
fi
log_info "SSH connected"

# Update system
log_step "Updating system packages..."
ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<'EOF'
set -euo pipefail
apk update
apk upgrade
EOF
log_info "System updated"

# Install essential dependencies
log_step "Installing essential dependencies..."
ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<'EOF'
set -euo pipefail
apk add --no-cache \
    git curl wget bash sudo \
    build-base linux-headers \
    ca-certificates openssl
EOF
log_info "Dependencies installed"

# Exit if provision-only mode
if [[ "$PROVISION_ONLY" = "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Provision Complete (system update only)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Connect to VM:"
    echo "  ssh -i $SSH_KEY root@$VM_IP"
    echo ""
    echo "Destroy when done:"
    echo "  ./scripts/destroy-vm.sh $VM_NAME"
    echo ""
    exit 0
fi

# Clone repository
REPO_NAME=$(basename "$REPO_URL" .git)
log_step "Cloning repository..."
ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<EOF
set -euo pipefail
mkdir -p $WORK_DIR
cd $WORK_DIR
if [[ -d "$REPO_NAME" ]]; then
    echo "Repository exists, pulling latest..."
    cd $REPO_NAME
    git pull
else
    git clone $REPO_URL
fi
EOF
log_info "Repository cloned"

# Auto-detect and install language dependencies
log_step "Detecting project type..."

# Python
if ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" "[[ -f $WORK_DIR/$REPO_NAME/requirements.txt ]] || [[ -f $WORK_DIR/$REPO_NAME/pyproject.toml ]]"; then
    log_info "Python project detected"
    ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<EOF
apk add --no-cache python3 py3-pip
cd $WORK_DIR/$REPO_NAME
[[ -f requirements.txt ]] && pip3 install -r requirements.txt
[[ -f pyproject.toml ]] && pip3 install .
EOF
fi

# Node.js
if ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" "[[ -f $WORK_DIR/$REPO_NAME/package.json ]]"; then
    log_info "Node.js project detected"
    ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<EOF
apk add --no-cache nodejs npm
cd $WORK_DIR/$REPO_NAME
npm install
EOF
fi

# Go
if ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" "[[ -f $WORK_DIR/$REPO_NAME/go.mod ]]"; then
    log_info "Go project detected"
    ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<EOF
apk add --no-cache go
cd $WORK_DIR/$REPO_NAME
go mod download
EOF
fi

# Rust
if ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" "[[ -f $WORK_DIR/$REPO_NAME/Cargo.toml ]]"; then
    log_info "Rust project detected"
    ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<EOF
apk add --no-cache rust cargo
cd $WORK_DIR/$REPO_NAME
cargo fetch
EOF
fi

# Make
if ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" "[[ -f $WORK_DIR/$REPO_NAME/Makefile ]]"; then
    log_info "Makefile detected"
    ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" "apk add --no-cache make cmake"
fi

# Run tests
log_step "Running tests: $TEST_COMMAND"
mkdir -p "$RESULTS_DIR"

ssh $SSH_OPTS -i "$SSH_KEY" root@"$VM_IP" <<EOF > "$RESULTS_DIR/test-output.log" 2>&1
set +e
cd $WORK_DIR/$REPO_NAME
echo "========================================="
echo "Test Execution Started"
echo "Repository: $REPO_URL"
echo "Command: $TEST_COMMAND"
echo "Timestamp: \$(date)"
echo "========================================="
echo ""
$TEST_COMMAND
TEST_EXIT=\$?
echo ""
echo "========================================="
echo "Test Complete - Exit Code: \$TEST_EXIT"
echo "========================================="
exit \$TEST_EXIT
EOF

TEST_EXIT=$?
echo $TEST_EXIT > "$RESULTS_DIR/exit-code.txt"

if [[ $TEST_EXIT -eq 0 ]]; then
    log_info "Tests PASSED"
    echo "PASSED" > "$RESULTS_DIR/status.txt"
else
    log_warn "Tests FAILED (exit code: $TEST_EXIT)"
    echo "FAILED" > "$RESULTS_DIR/status.txt"
fi

# Save metadata
cat > "$RESULTS_DIR/metadata.txt" <<METADATA
VM Name: $VM_NAME
VM IP: $VM_IP
Repository: $REPO_URL
Test Command: $TEST_COMMAND
Timestamp: $(date)
Exit Code: $TEST_EXIT
Status: $(cat "$RESULTS_DIR/status.txt")
METADATA

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Provisioning Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "VM: $VM_NAME ($VM_IP)"
echo "Repository: $REPO_URL"
echo "Test Status: $(cat "$RESULTS_DIR/status.txt")"
echo "Exit Code: $TEST_EXIT"
echo ""
echo "Results: $RESULTS_DIR/"
echo "  - test-output.log"
echo "  - status.txt"
echo "  - exit-code.txt"
echo "  - metadata.txt"
echo ""
echo "View results:"
echo "  cat $RESULTS_DIR/test-output.log"
echo ""
echo "Connect to VM:"
echo "  ssh -i $SSH_KEY root@$VM_IP"
echo "  cd $WORK_DIR/$REPO_NAME"
echo ""
echo "Destroy when done:"
echo "  ./scripts/destroy-vm.sh $VM_NAME"
echo ""

exit $TEST_EXIT
