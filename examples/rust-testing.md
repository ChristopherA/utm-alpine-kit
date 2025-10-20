# Rust Testing Example

Complete workflow for testing Rust projects using Alpine VM Manager.

## Overview

This example demonstrates the deploy-test-destroy cycle for a Rust project, from template creation through automated testing.

**Use case:** Test Rust code in a clean Alpine environment before deploying to production.

**Time:** ~2 minutes per test cycle after initial template creation

## Prerequisites

- Alpine template created (see [setup guide](../docs/setup-macos.md))
- Rust project with standard `Cargo.toml` structure
- Tests defined in `src/` or `tests/` directory

## One-Time Setup

If you haven't created a template yet:

```bash
# Create Alpine template (5 minutes, one-time)
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso
```

## Example 1: Basic Rust Testing

Test a simple Rust library:

```bash
# 1. Clone VM
./scripts/clone-vm.sh rust-test-1

# Wait ~20 seconds for boot and IP detection
# Output will show: IP Address: 192.168.1.100

# 2. Provision and test
./scripts/provision-for-testing.sh \
  rust-test-1 \
  192.168.1.100 \
  https://github.com/user/rust-library.git \
  "cargo test"

# Script will:
# - Update Alpine packages
# - Install rust, cargo, build-base
# - Clone repository to /root/testing/
# - Run cargo fetch to download dependencies
# - Execute cargo test
# - Save results to ./results/YYYYMMDD-HHMMSS/

# 3. Destroy VM
./scripts/destroy-vm.sh rust-test-1 --yes
```

**Total time:** ~2 minutes (varies with test suite size)

## Example 2: Rust with Additional Dependencies

Test a Rust project that requires OpenSSL:

```bash
# Clone VM
./scripts/clone-vm.sh rust-openssl-test

# Get IP from output
VM_IP="192.168.1.101"

# Provision system packages first
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<'EOF'
set -euo pipefail

# Update system
apk update && apk upgrade

# Install Rust and build dependencies
apk add --no-cache \
  rust cargo \
  build-base \
  openssl-dev \
  pkgconf

# Verify installations
rustc --version
cargo --version
EOF

# Clone and test project
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<'EOF'
cd /root
git clone https://github.com/user/rust-openssl-project.git
cd rust-openssl-project

# Build and test
cargo build --release
cargo test --release

# Run specific test
cargo test --test integration_tests
EOF

# Destroy when done
./scripts/destroy-vm.sh rust-openssl-test --yes
```

## Example 3: Multi-Target Testing

Test Rust code on different configurations:

```bash
# Test with minimal resources (256MB RAM)
./scripts/clone-vm.sh rust-minimal --ram 0.25 --cpu 1
./scripts/provision-for-testing.sh \
  rust-minimal \
  192.168.1.102 \
  https://github.com/user/rust-project.git \
  "cargo test"

# Test with ample resources (2GB RAM)
./scripts/clone-vm.sh rust-large --ram 2 --cpu 4
./scripts/provision-for-testing.sh \
  rust-large \
  192.168.1.103 \
  https://github.com/user/rust-project.git \
  "cargo test --release"

# Compare results
diff results/20251019-120000/test-output.log \
     results/20251019-120130/test-output.log

# Cleanup
./scripts/destroy-vm.sh rust-minimal --yes
./scripts/destroy-vm.sh rust-large --yes
```

## Example 4: Parallel Testing

Run multiple test suites simultaneously:

```bash
# Start multiple VMs in parallel
./scripts/clone-vm.sh rust-unit &
./scripts/clone-vm.sh rust-integration &
./scripts/clone-vm.sh rust-doc &
wait

# Get IPs (example)
VM_UNIT="192.168.1.104"
VM_INTEGRATION="192.168.1.105"
VM_DOC="192.168.1.106"

# Run tests in parallel
./scripts/provision-for-testing.sh \
  rust-unit $VM_UNIT \
  https://github.com/user/rust-project.git \
  "cargo test --lib" &

./scripts/provision-for-testing.sh \
  rust-integration $VM_INTEGRATION \
  https://github.com/user/rust-project.git \
  "cargo test --test '*'" &

./scripts/provision-for-testing.sh \
  rust-doc $VM_DOC \
  https://github.com/user/rust-project.git \
  "cargo test --doc" &

# Wait for all to complete
wait

# Check results
for dir in results/*/; do
  echo "$(basename $dir): $(cat $dir/status.txt)"
done

# Cleanup all
./scripts/destroy-vm.sh rust-unit --yes
./scripts/destroy-vm.sh rust-integration --yes
./scripts/destroy-vm.sh rust-doc --yes
```

## Example 5: Benchmarking

Run Rust benchmarks in isolated environment:

```bash
# Clone with extra resources for benchmarking
./scripts/clone-vm.sh rust-bench --ram 4 --cpu 4

VM_IP="192.168.1.107"

# Install nightly Rust for benchmarks
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<'EOF'
apk update && apk add rust cargo build-base

# Install rustup for nightly
apk add rustup
rustup-init -y --default-toolchain nightly
source $HOME/.cargo/env

# Clone project
cd /root
git clone https://github.com/user/rust-project.git
cd rust-project

# Run benchmarks
cargo +nightly bench

# Save results
cargo +nightly bench > /root/bench-results.txt
EOF

# Retrieve benchmark results
scp -i ~/.ssh/id_ed25519_alpine_vm \
  root@$VM_IP:/root/bench-results.txt \
  ./bench-results-$(date +%Y%m%d-%H%M%S).txt

# Destroy VM
./scripts/destroy-vm.sh rust-bench --yes
```

## Example 6: Cross-Compilation Testing

Test ARM64 binaries built on Alpine:

```bash
# Clone VM
./scripts/clone-vm.sh rust-arm64-test

VM_IP="192.168.1.108"

# Build and test ARM64 binary
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<'EOF'
apk update && apk add rust cargo build-base git

# Clone project
cd /root
git clone https://github.com/user/rust-cli-tool.git
cd rust-cli-tool

# Build release binary
cargo build --release --target=aarch64-unknown-linux-musl

# Test the binary
./target/release/rust-cli-tool --version
./target/release/rust-cli-tool --help

# Run integration tests
cargo test --release
EOF

# Retrieve binary
mkdir -p builds/
scp -i ~/.ssh/id_ed25519_alpine_vm \
  root@$VM_IP:/root/rust-cli-tool/target/release/rust-cli-tool \
  builds/rust-cli-tool-alpine-arm64

# Verify it's a static binary
file builds/rust-cli-tool-alpine-arm64
# Should show: ELF 64-bit LSB executable, ARM aarch64, statically linked

# Destroy VM
./scripts/destroy-vm.sh rust-arm64-test --yes
```

## Example 7: Full CI/CD Workflow

Automated testing script for CI/CD:

```bash
#!/bin/bash
# ci-test.sh - Automated Rust testing workflow

set -euo pipefail

PROJECT_URL="https://github.com/user/rust-project.git"
VM_NAME="rust-ci-$(date +%s)"
RESULTS_BASE="./ci-results"

# Create results directory
mkdir -p "$RESULTS_BASE"

# Clone VM
./scripts/clone-vm.sh "$VM_NAME" --ram 2 --cpu 2

# Get IP
sleep 15
VM_IP=$(utmctl ip-address "$VM_NAME" | head -1)

if [[ -z "$VM_IP" ]]; then
  echo "Failed to get VM IP"
  ./scripts/destroy-vm.sh "$VM_NAME" --yes
  exit 1
fi

# Run tests
if ./scripts/provision-for-testing.sh "$VM_NAME" "$VM_IP" "$PROJECT_URL" "cargo test --all"; then
  echo "✅ Tests passed"
  TEST_RESULT="success"
else
  echo "❌ Tests failed"
  TEST_RESULT="failure"
fi

# Copy latest results
LATEST_RESULT=$(ls -t results/ | head -1)
cp -r "results/$LATEST_RESULT" "$RESULTS_BASE/$(date +%Y%m%d-%H%M%S)-$TEST_RESULT"

# Cleanup
./scripts/destroy-vm.sh "$VM_NAME" --yes

# Exit with test result
[[ "$TEST_RESULT" == "success" ]] && exit 0 || exit 1
```

Usage:

```bash
chmod +x ci-test.sh
./ci-test.sh
```

## Common Rust Dependencies on Alpine

```bash
# Basic Rust development
apk add rust cargo build-base

# OpenSSL
apk add openssl-dev pkgconf

# SQLite
apk add sqlite-dev

# PostgreSQL client
apk add postgresql-dev

# MySQL/MariaDB client
apk add mariadb-dev

# Protobuf
apk add protobuf-dev

# Additional build tools
apk add cmake make git
```

## Rust-Specific Tips

### Faster Builds with Caching

Create a template with pre-installed Rust and common dependencies:

```bash
# Create base template
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso \
  --name alpine-rust-template

# Start and provision it
utmctl start alpine-rust-template
VM_IP=$(utmctl ip-address alpine-rust-template | head -1)

ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<'EOF'
apk update && apk add \
  rust cargo build-base \
  git curl wget \
  openssl-dev sqlite-dev \
  pkgconf cmake make

# Verify
cargo --version
rustc --version
EOF

# Stop template
utmctl stop alpine-rust-template

# Now clone from this template instead
./scripts/clone-vm.sh my-rust-test --template alpine-rust-template
```

### musl vs glibc

Alpine uses musl libc instead of glibc. Most Rust code works fine, but:

```bash
# For static binaries (recommended)
cargo build --target=aarch64-unknown-linux-musl

# If you need glibc compatibility
apk add gcompat
```

### Cargo Cache

The provision script doesn't cache Cargo dependencies between runs. For frequent testing:

```bash
# Create a template with pre-downloaded dependencies
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP <<'EOF'
cd /root
git clone https://github.com/user/rust-project.git
cd rust-project
cargo fetch  # Downloads all dependencies
EOF

# Stop and save as template
utmctl stop rust-project-cached

# Clone this for faster subsequent tests
```

## Performance Considerations

**Small projects (<1000 LOC):**
- 512MB RAM, 1-2 CPUs sufficient
- Total cycle: 1-2 minutes

**Medium projects (1000-10000 LOC):**
- 1-2GB RAM, 2-4 CPUs recommended
- Total cycle: 3-5 minutes

**Large projects (>10000 LOC):**
- 4GB+ RAM, 4 CPUs
- Consider pre-cached dependency template
- Total cycle: 5-10 minutes

## Next Steps

- Adapt for [Python projects](python-testing.md) (coming soon)
- Adapt for [Node.js projects](nodejs-testing.md) (coming soon)
- Learn more about [template creation](../docs/template-creation.md)
- See [troubleshooting guide](../docs/troubleshooting.md) for common issues
