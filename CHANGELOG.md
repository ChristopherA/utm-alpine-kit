# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.00] - 2025-10-19

### Added
- **Complete automation suite** for Alpine Linux VM management on UTM
- **One-command template creation** (~5 minutes from ISO to ready-to-clone template)
- **Answer file automation** for unattended Alpine installation
  - Template-based answer file with SSH key injection
  - HTTP server integration for answer file delivery
  - Expect script automation for handling interactive prompts
- **Serial console automation** via TCP mode (port 4444)
- **Fast VM cloning** with automatic configuration
  - MAC address regeneration for unique DHCP leases
  - RAM/CPU resizing via PlistBuddy
  - Automatic IP detection via QEMU guest agent
- **Language-detecting provisioning** for automated testing
  - Auto-detects Python, Node.js, Go, Rust projects
  - Installs dependencies automatically
  - Runs tests and captures results
- **Complete documentation** (2,500+ lines)
  - macOS setup guide (420 lines)
  - Template creation technical deep dive (540 lines)
  - UTM fundamentals guide (538 lines)
  - Alpine Linux quick reference (457 lines)
  - GRUB boot fix guide (200 lines)
  - Troubleshooting guide (570 lines)
  - Rust testing examples (450 lines)
- **Production scripts** (1,700+ lines)
  - `create-alpine-template.sh` - Automated template creation (450 lines)
  - `clone-vm.sh` - VM cloning with resource customization (285 lines)
  - `provision-for-testing.sh` - Language-detecting provisioning (270 lines)
  - `destroy-vm.sh` - Clean VM destruction (195 lines)
  - `list-templates.sh` - VM inventory management (125 lines)
  - Library scripts for installation automation

### Technical Achievements
- **AppleScript VM creation** - Solved boot order problem that prevented plist-only automation
- **GRUB module loading fix** - Alpine-specific solution for clean boot (prepend insmod to grub.cfg)
- **Answer file discoveries** - Documented ROOTPASS and DISKOPTS limitations
- **UTM configuration caching workflow** - Proper quit/edit/restart UTM pattern
- **Deploy-test-destroy cycle** - Complete workflow in <2 minutes

### Known Limitations
- **No security review** - Code functional but not yet hardened for production use
- **Single-user tested** - Awaiting community feedback and bug reports
- **ARM64 only** - Tested exclusively on Apple Silicon Macs
- **macOS specific** - UTM automation patterns specific to macOS environment

### Dependencies
- macOS with Apple Silicon (ARM64)
- UTM 4.0+
- Homebrew (for `expect` installation)
- Alpine Linux 3.22 virt ISO

### Origin
Developed for real-world P2P protocol testing (Tor, Lightning Network, BitTorrent DHT). Proven in production use for rapid deploy-test-destroy workflows.

## Version History

- **0.2.00** (2025-10-19) - Initial public release with complete automation
- **0.1.00** (2025-10-09) - Internal development version (not released)

---

**Note:** Version 1.0.0 will be released after:
- External users successfully deploy and provide feedback
- Community testing and bug reports addressed
- Security review completed (if applicable)
- Documentation validated by multiple users
