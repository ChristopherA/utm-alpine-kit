# UTM Alpine Kit

> - _did_: `did:repo:7173557/blob/main/README.md`
> - _github_: [`utm-alpine-kit/README.md`](https://github.com/ChristopherA/utm-alpine-kit/blob/main/README.md)
> - _purpose_: Automated Alpine Linux VM creation and management for UTM on macOS
> - _copyright_: ©2025 by @ChristopherA, licensed under [BSD 2-Clause Plus Patent License](https://spdx.org/licenses/BSD-2-Clause-Patent.html)
> - _created_: 2025-10-19 by @ChristopherA <ChristopherA@LifeWithAlacrity.com>
> - _last-updated_: 2025-10-25 by @ChristopherA <ChristopherA@LifeWithAlacrity.com>

[![License](https://img.shields.io/badge/License-BSD_2--Clause--Patent-blue.svg)](LICENSE.md)
[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)

Fast, reproducible Alpine Linux development environments for UTM on macOS. Automated template creation, instant cloning, and deploy-test-destroy workflows.

**📚 Related Resources:**
- [Alpine UTM Guide](https://gist.github.com/ChristopherA/39b5a9b51dd0ff7eac79da339aa233ee) - Alpine-specific automation knowledge and hard-won lessons
- [UTM Automation Guide](https://gist.github.com/ChristopherA/96232f85893054b0ac4b4a04d08d8821) - Generic UTM/QEMU automation patterns

## Overview

UTM Alpine Kit provides a complete automation suite for creating and managing lightweight Alpine Linux virtual machines on macOS using UTM. Perfect for developers who need quick, disposable test environments.

**Key Features:**
- One-command template creation (~2 minutes)
- Instant VM cloning (0-1 second) with automatic network configuration
- Dual authentication: SSH key + password for flexibility
- Automated IP detection via qemu-guest-agent
- Minimal resource usage (512MB RAM, 171MB disk per VM)
- Deploy-test-destroy cycle in minutes

**Why Alpine Linux?**
- Purpose-built for containers and VMs
- Minimal footprint (~500MB installed)
- Fast boot time (<5 seconds)
- Stable, predictable package management
- Built-in automation support

**Tested Environment:** Alpine Linux 3.22, UTM 4.x, macOS Tahoe 26.x, ARM64 (M-series)

**Origin:** Developed for real-world P2P protocol testing (Tor, Lightning Network, BitTorrent DHT). Proven in production use for rapid deploy-test-destroy workflows.

## Quick Start

### Prerequisites

1. **macOS** with Apple Silicon (ARM64)
2. **UTM** 4.0+ installed ([download](https://mac.getutm.app/))
3. **Homebrew** for installing utilities
4. **Alpine ISO** downloaded (see Setup below)

### One-Time Setup

```bash
# Install utilities
brew install expect

# Create SSH key for VM access
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_alpine_vm -C "utm-alpine-kit"

# Download Alpine ISO (ARM64 virtual image)
mkdir -p ~/.cache/vms
cd ~/.cache/vms
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-virt-3.22.0-aarch64.iso

# Clone this repository
git clone https://github.com/ChristopherA/utm-alpine-kit.git
cd utm-alpine-kit
```

For detailed setup instructions, see [docs/setup-macos.md](docs/setup-macos.md).

### Create Template (One-Time)

Create a reusable Alpine template once:

```bash
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso
```

This takes ~2 minutes and creates `alpine-template.utm` - a clean, minimal Alpine installation ready for cloning.

**What it does:**
- Creates and configures UTM VM (20GB disk, 2GB RAM, 2 CPUs)
- Installs Alpine Linux via answer file automation
- Configures both SSH key and password authentication
- Installs qemu-guest-agent for automatic IP detection
- Syncs filesystem and verifies SSH keys persist
- Removes ISO and prepares for instant cloning

See [docs/template-creation.md](docs/template-creation.md) for details.

### Daily Workflow: Clone → Test → Destroy

Once you have a template, use this fast cycle for testing:

#### 1. Clone VM

```bash
# Basic clone (uses template's defaults)
./scripts/clone-vm.sh test-vm-1

# Clone with custom resources
./scripts/clone-vm.sh test-vm-2 --ram 4 --cpu 2

# Clone from specific template
./scripts/clone-vm.sh my-test --template alpine-minimal
```

**Time:** 0-1 second (instant duplication)
**Result:** Fresh Alpine VM with new MAC address, ready in ~25 seconds

#### 2. Test Your Code

```bash
# Provision and test (auto-detects language)
./scripts/provision-for-testing.sh test-vm-1 192.168.1.100 \
  https://github.com/user/repo.git

# Custom test command
./scripts/provision-for-testing.sh test-vm-1 192.168.1.100 \
  https://github.com/user/repo.git "cargo test"

# Or SSH in manually
ssh -i ~/.ssh/id_ed25519_alpine_vm root@192.168.1.100
```

**Time:** Varies (depends on tests)
**Features:**
- Auto-updates system packages
- Detects Python, Node, Go, Rust projects
- Installs dependencies automatically
- Runs tests and saves results

#### 3. Destroy VM

```bash
./scripts/destroy-vm.sh test-vm-1
```

**Time:** <10 seconds
**Cleanup:** Stops VM, deletes bundle, cleans SSH known_hosts

## Complete Workflow Example

```bash
# Create template (one-time)
./scripts/create-alpine-template.sh \
  --iso ~/.cache/vms/alpine-virt-3.22.0-aarch64.iso

# Clone for testing
./scripts/clone-vm.sh rust-test

# Provision and test a Rust project
./scripts/provision-for-testing.sh rust-test 192.168.1.100 \
  https://github.com/user/rust-project.git "cargo test"

# Destroy when done
./scripts/destroy-vm.sh rust-test --yes
```

## Project Structure

```
utm-alpine-kit/
├── scripts/
│   ├── create-alpine-template.sh    # Create template (one-time)
│   ├── clone-vm.sh                  # Clone template for testing
│   ├── provision-for-testing.sh     # Provision and test code
│   ├── destroy-vm.sh                # Clean up VM
│   ├── list-templates.sh            # List available VMs
│   └── lib/                         # Library scripts
│       ├── install-via-answerfile.exp
│       └── install-disk.exp
├── templates/
│   └── alpine-template.answers      # Answer file template
├── docs/
│   ├── setup-macos.md              # Detailed setup guide
│   ├── template-creation.md        # Template creation details
│   └── troubleshooting.md          # Common issues and fixes
└── examples/
    └── rust-testing.md             # Example workflows
```

## Documentation

### Getting Started
- **[Setup Guide](docs/setup-macos.md)** - Complete macOS setup from scratch
- **[Template Creation](docs/template-creation.md)** - How templates work

### Essential Knowledge
- **[UTM Fundamentals](docs/utm-fundamentals.md)** - UTM automation concepts (config caching, AppleScript, serial console)
- **[Alpine Reference](docs/alpine-reference.md)** - Alpine Linux quick reference (apk, OpenRC, commands)
- **[GRUB Boot Fix](docs/grub-boot-fix.md)** - Fix Alpine GRUB boot errors (required for clean boot)

### Reference
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## Examples

- **[Rust Testing](examples/rust-testing.md)** - Test Rust projects
- More examples TBD (Python, Node.js, Go workflows)

## Requirements

- **macOS:** Apple Silicon (ARM64) required
- **UTM:** Version 4.0 or later
- **RAM:** 4GB free (per VM: 512MB default, configurable)
- **Disk:** 10GB free (per VM: 1-2GB typical)
- **Network:** Bridged mode (UTM default for ARM)

## How It Works

### Template Creation
1. Creates UTM VM with virtual disk
2. Boots Alpine ISO with serial console automation
3. Runs `setup-alpine` with answer file via HTTP
4. Executes `setup-disk` for disk installation
5. Reboots, removes ISO, sets password via SSH
6. Template ready for cloning

### Automation Technology
- **Answer Files:** Unattended Alpine installation
- **Serial Console:** TcpServer mode for automation
- **Expect Scripts:** Interactive prompt handling
- **QEMU Guest Agent:** IP address detection
- **PlistBuddy:** UTM configuration modification

### Clone Workflow
1. Duplicates template VM bundle
2. Generates new random MAC address
3. Optionally resizes RAM/CPU via PlistBuddy
4. Restarts UTM to load configuration
5. Starts VM and detects IP via guest agent

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for detailed solutions.

**Common issues:**
- **No IP detected:** Wait 15-25 seconds for qemu-guest-agent to start
- **SSH key fails:** Both key and password auth are configured; verify key path
- **Clone hangs:** Ensure template is stopped before cloning
- **UTM config not updating:** UTM caches configs - restart UTM to reload

## Contributing

Contributions welcome! Please:
1. Test changes on a fresh Alpine template
2. Follow existing script style and documentation
3. Update relevant docs
4. Submit PRs with clear descriptions

## Support This Project

If you find this project valuable, consider supporting my open source and digital civil rights advocacy efforts.

I work to represent smaller developers in a vendor-neutral, platform-neutral way, advancing the open web, digital civil liberties, and human rights. Your sponsorship helps sustain this work and ensures I can continue creating resources like this project.

**Become a sponsor:** [GitHub Sponsors](https://github.com/sponsors/ChristopherA) (from $5/month)

This isn't just a transaction—it's an opportunity to plug into a network advancing the digital commons. Let's collaborate!

## License

BSD-2-Clause-Plus-Patent License

See [LICENSE.md](LICENSE.md) for details.

## Author

**Christopher Allen**
* 📧 <ChristopherA@LifeWithAlacrity.com>
* 🐙 [@ChristopherA](https://github.com/ChristopherA)
* 🦋 [@ChristopherA.bsky.social](https://bsky.app/profile/christophera.bsky.social)
* 🅧 [@ChristopherA](https://twitter.com/ChristopherA)

Used by Blockchain Commons for testing secure development workflows.

## Related Resources

- [Alpine Linux](https://alpinelinux.org/)
- [UTM Virtual Machines](https://mac.getutm.app/)
- [UTM Automation Guide](https://gist.github.com/ChristopherA/96232f85893054b0ac4b4a04d08d8821)
- [Alpine UTM Guide](https://gist.github.com/ChristopherA/39b5a9b51dd0ff7eac79da339aa233ee)

## Community

- **Issues:** [GitHub Issues](https://github.com/ChristopherA/utm-alpine-kit/issues)
- **Discussions:** [GitHub Discussions](https://github.com/ChristopherA/utm-alpine-kit/discussions)
