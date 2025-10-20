# Alpine Linux Quick Reference

**Essential Alpine Linux commands for utm-alpine-kit users.**

This guide covers the Alpine-specific tools and commands you'll use when working with Alpine VMs. If you're coming from Debian/Ubuntu or other distributions, this will help you get productive quickly.

## Key Differences from Other Distributions

| Feature | Alpine | Debian/Ubuntu | Notes |
|---------|--------|---------------|-------|
| **Package Manager** | `apk` | `apt` | Different commands |
| **Init System** | OpenRC | systemd | Different service management |
| **C Library** | musl libc | glibc | Some binary packages won't work |
| **Size** | ~500MB | ~2GB+ | Minimal footprint |
| **Package Availability** | Main/Community/Testing | Main/Universe/Multiverse | Smaller repository |

## Package Management (apk)

### Basic Commands

```bash
# Update package index (do this first!)
apk update

# Upgrade all installed packages
apk upgrade

# Install package
apk add <package>

# Install without caching (saves space)
apk add --no-cache <package>

# Install multiple packages
apk add package1 package2 package3

# Remove package
apk del <package>

# Search for packages
apk search <query>

# Get package information
apk info <package>

# List installed packages
apk list --installed

# List files in package
apk info -L <package>
```

### Common Packages for Development

```bash
# Build tools
apk add build-base gcc musl-dev

# Version control
apk add git

# Editors
apk add nano vim

# Network tools
apk add curl wget

# Programming languages
apk add python3 py3-pip      # Python
apk add nodejs npm           # Node.js
apk add go                   # Go
apk add rust cargo           # Rust

# Debugging tools
apk add tcpdump netcat-openbsd bind-tools
apk add iftop nethogs iperf3

# SSH and remote access
apk add openssh openssh-client
```

### Repository Management

Alpine has three repository tiers:
- **main**: Core packages, officially supported
- **community**: Community-maintained packages (most development tools)
- **testing**: Bleeding-edge packages (use with caution)

**View current repositories:**
```bash
cat /etc/apk/repositories
```

**Example output:**
```
https://dl-cdn.alpinelinux.org/alpine/v3.22/main
https://dl-cdn.alpinelinux.org/alpine/v3.22/community
```

**Enable testing repo (if needed):**
```bash
echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
apk update
```

**Note:** Testing repo can cause conflicts. Only add if you need cutting-edge packages.

### Common Package Issues

**"ERROR: Unable to lock database"**
```bash
# Another apk process is running, wait or kill:
pkill apk
rm -f /var/cache/apk/lock
```

**"UNTRUSTED signature"**
```bash
# System clock is wrong
date
# Fix timezone
setup-timezone
# Sync hardware clock
hwclock -s
apk update
```

**"No such package: X"**
```bash
# Package index not updated
apk update

# Or package is in different repo
apk search <package-name>
# Check which repo it's in
```

## Service Management (OpenRC)

### rc-update: Configure Services

```bash
# Add service to runlevel
rc-update add <service> <runlevel>

# Remove service from runlevel
rc-update del <service> <runlevel>

# Show all services and runlevels
rc-update show

# Show services in specific runlevel
rc-update show default
```

**Common runlevels:**
- `boot` - Early boot (networking, hostname)
- `default` - Normal operation (sshd, services)
- `shutdown` - System shutdown

### rc-service: Control Services

```bash
# Start service
rc-service <service> start

# Stop service
rc-service <service> stop

# Restart service
rc-service <service> restart

# Check status
rc-service <service> status

# List all services
rc-service --list
```

### Common Service Tasks

**SSH server:**
```bash
# Enable SSH on boot
rc-update add sshd default

# Start SSH now
rc-service sshd start

# Check SSH status
rc-service sshd status
```

**QEMU guest agent (required for IP detection):**
```bash
# Enable on boot
rc-update add qemu-guest-agent default

# Start now
rc-service qemu-guest-agent start

# Verify it's running
rc-service qemu-guest-agent status
```

**Networking:**
```bash
# Enable networking on boot
rc-update add networking boot

# Restart networking
rc-service networking restart

# Check network status
rc-service networking status
```

**System logging:**
```bash
# Enable syslog
rc-update add syslog default
rc-service syslog start

# View logs
tail -f /var/log/messages
```

### Service Logs

OpenRC logs to syslog:

```bash
# View system log
tail -f /var/log/messages

# Service-specific logs (if configured)
ls /var/log/

# Boot messages
dmesg | less

# Check last boot
dmesg | grep -i error
```

## Networking

### DHCP Configuration (Default)

Template VMs use DHCP by default. Configuration in `/etc/network/interfaces`:

```bash
# View current network config
cat /etc/network/interfaces
```

**Example DHCP config:**
```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
```

### Static IP Configuration

To set a static IP (uncommon for utm-alpine-kit):

```bash
# Edit network config
nano /etc/network/interfaces
```

**Change to:**
```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
```

**Apply changes:**
```bash
rc-service networking restart
```

### Network Troubleshooting

```bash
# Check IP address
ip addr show eth0

# Check routing
ip route

# Test connectivity
ping -c 4 8.8.8.8

# Check DNS
nslookup google.com

# View network stats
netstat -tunlp
```

## File System

### Disk Usage

```bash
# Disk space
df -h

# Directory sizes
du -sh /var/log/*

# Largest files
du -h /root | sort -h | tail -20

# Inodes usage
df -i
```

### Common Locations

```bash
# Package cache
/var/cache/apk/

# Logs
/var/log/

# Service configs
/etc/

# Temporary files
/tmp/

# User home
/root/
```

## User Management

Alpine templates use root by default for simplicity. For production:

```bash
# Add user
adduser username

# Add user to group
adduser username wheel

# Configure sudo
apk add sudo
echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
```

## System Information

```bash
# Alpine version
cat /etc/alpine-release

# Kernel version
uname -r

# Architecture
uname -m

# CPU info
cat /proc/cpuinfo

# Memory info
free -h

# Disk info
lsblk
```

## musl libc Considerations

Alpine uses musl libc instead of glibc. This affects:

**Binary packages:**
- Some pre-compiled binaries won't work
- Example: Official Rust binaries from rust-lang.org
- Solution: Use Alpine packages (`apk add rust`)

**Dynamic libraries:**
- Look for `musl` instead of `glibc`
- Path: `/lib/ld-musl-*.so.1`

**Most source code works fine:**
- Compile from source using Alpine's build-base
- Use Alpine packages when available

**If you need glibc:**
```bash
# Install gcompat (glibc compatibility layer)
apk add gcompat

# Note: Not all glibc programs will work
```

## Useful One-Liners

```bash
# Update system
apk update && apk upgrade

# Install common development tools
apk add build-base git curl wget nano vim

# Clean package cache (free space)
rm -rf /var/cache/apk/*

# Reinstall all packages (if corrupted)
apk fix

# Show largest installed packages
apk info -s | sort -k2 -h

# Find package providing a file
apk info --who-owns /usr/bin/git
```

## Alpine vs Debian/Ubuntu Command Comparison

| Task | Alpine | Debian/Ubuntu |
|------|--------|---------------|
| Update packages | `apk update` | `apt update` |
| Upgrade packages | `apk upgrade` | `apt upgrade` |
| Install package | `apk add pkg` | `apt install pkg` |
| Remove package | `apk del pkg` | `apt remove pkg` |
| Search packages | `apk search pkg` | `apt search pkg` |
| Enable service | `rc-update add svc default` | `systemctl enable svc` |
| Start service | `rc-service svc start` | `systemctl start svc` |
| Check status | `rc-service svc status` | `systemctl status svc` |
| View logs | `tail /var/log/messages` | `journalctl -xe` |

## Further Reading

For comprehensive Alpine Linux knowledge:
- [Alpine UTM Guide - Package Management](https://gist.github.com/ChristopherA/39b5a9b51dd0ff7eac79da339aa233ee#alpine-package-management-apk)
- [Alpine UTM Guide - Service Management](https://gist.github.com/ChristopherA/39b5a9b51dd0ff7eac79da339aa233ee#alpine-service-management-openrc)
- [Alpine Linux Documentation](https://wiki.alpinelinux.org/)

For utm-alpine-kit specific:
- [Template Creation](template-creation.md) - How templates work
- [Troubleshooting](troubleshooting.md) - Common issues
- [GRUB Boot Fix](grub-boot-fix.md) - Fix boot errors
