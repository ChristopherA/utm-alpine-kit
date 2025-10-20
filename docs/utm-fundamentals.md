# UTM Automation Fundamentals

**Essential UTM concepts for utm-alpine-kit users.**

This guide covers the UTM-specific automation knowledge you need to understand how utm-alpine-kit works and troubleshoot issues.

## UTM Architecture

UTM is a macOS GUI wrapper around QEMU, the industry-standard virtualization engine.

```
┌─────────────────────────────────┐
│  UTM.app (macOS GUI)            │
│  - VM management interface      │
│  - Configuration UI             │
│  - utmctl command-line tool     │
└────────────┬────────────────────┘
             │
┌────────────▼────────────────────┐
│  QEMU (Virtualization Engine)   │
│  - Actual hypervisor            │
│  - Hardware emulation           │
│  - Guest agent communication    │
└─────────────────────────────────┘
```

**Key components:**
- **UTM.app** - User interface and VM management
- **config.plist** - VM configuration file (XML format)
- **utmctl** - Command-line tool for scripting
- **QEMU** - Underlying virtualization engine
- **Guest Agent** - Enables host↔VM communication

## Critical: UTM Configuration Caching

**🚨 MOST IMPORTANT CONCEPT FOR AUTOMATION**

UTM loads `config.plist` into memory when it launches. Changes to the config file while UTM is running **have NO effect** until you restart UTM.

### The Problem

```bash
# ❌ This doesn't work:
vim ~/Library/Containers/com.utmapp.UTM/Data/Documents/my-vm.utm/config.plist
# Edit file...
utmctl start my-vm
# VM starts with OLD configuration!
```

### The Solution

**Always quit UTM before editing config.plist:**

```bash
# 1. Quit UTM
osascript -e 'quit app "UTM"'
sleep 3

# 2. Edit config.plist
/usr/libexec/PlistBuddy -c "Set :Memory 4096" config.plist

# 3. Restart UTM
open -a UTM
sleep 5

# 4. Now start VM with new config
utmctl start my-vm
```

**Why this matters:**
- Clone scripts modify RAM/CPU in config.plist
- Must restart UTM for changes to take effect
- Serial console configuration requires UTM restart
- MAC address changes need UTM restart

**This is not a bug** - it's how UTM is designed.

## VM Configuration (config.plist)

Every VM has a `config.plist` file containing all settings.

**Location:**
```
~/Library/Containers/com.utmapp.UTM/Data/Documents/<vm-name>.utm/config.plist
```

**Format:** Apple Property List (XML)

**Editing tool:** `/usr/libexec/PlistBuddy` (built into macOS)

### Common PlistBuddy Operations

**Read a value:**
```bash
/usr/libexec/PlistBuddy -c "Print :Memory" config.plist
```

**Set a value:**
```bash
/usr/libexec/PlistBuddy -c "Set :Memory 4096" config.plist
```

**Add a value:**
```bash
/usr/libexec/PlistBuddy -c "Add :SerialPorts:0:Mode string TcpServer" config.plist
```

**Delete a value:**
```bash
/usr/libexec/PlistBuddy -c "Delete :Drive:0" config.plist
```

**Print entire config:**
```bash
/usr/libexec/PlistBuddy -c "Print" config.plist
```

### Key Configuration Keys

| Key | Type | Purpose | Example |
|-----|------|---------|---------|
| `:Memory` | integer | RAM in MB | `4096` (4GB) |
| `:CPU` | integer | CPU cores | `2` |
| `:Network:0:MacAddress` | string | MAC address | `"12:34:56:78:9A:BC"` |
| `:SerialPorts:0:Mode` | string | Serial console mode | `"TcpServer"` |
| `:SerialPorts:0:TcpPort` | integer | Serial console port | `4444` |
| `:Drive:0:ImagePath` | string | Disk image path | `"disk.qcow2"` |

**Note:** Array indices start at 0 (`:Drive:0`, `:Network:0`, etc.)

### Example: Resize VM

```bash
VM_PATH="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/my-vm.utm"
CONFIG="$VM_PATH/config.plist"

# Stop UTM
osascript -e 'quit app "UTM"'
sleep 3

# Modify configuration
/usr/libexec/PlistBuddy -c "Set :Memory 8192" "$CONFIG"  # 8GB RAM
/usr/libexec/PlistBuddy -c "Set :CPU 4" "$CONFIG"         # 4 CPUs

# Restart UTM
open -a UTM
sleep 5

# Start VM with new resources
utmctl start my-vm
```

## VM Creation: Why AppleScript?

**There is no `utmctl create` command.** To create VMs programmatically, you must use AppleScript.

### The Challenge

Manual VM creation via GUI is fine for one-off VMs, but automation requires:
- Creating VM from ISO
- Setting resources (RAM, CPU, disk)
- Configuring networking
- Setting boot order correctly

### The Solution: AppleScript

UTM provides an AppleScript interface for VM creation:

```applescript
#!/usr/bin/osascript
tell application "UTM"
    set isoPath to POSIX file "/path/to/alpine.iso"

    set newVM to make new virtual machine with properties {¬
        backend:qemu, ¬
        configuration:{¬
            name:"my-vm", ¬
            architecture:"aarch64", ¬
            memory:2048, ¬
            cpu cores:2, ¬
            drives:{¬
                {removable:true, source:isoPath}, ¬
                {guest size:20480}¬
            }, ¬
            network interfaces:{{mode:bridged}}, ¬
            displays:{{hardware:"virtio-gpu-gl-pci"}}¬
        }¬
    }
end tell
```

**Why AppleScript works where plist editing fails:**
- UTM's AppleScript interface correctly sets boot order
- Manual plist editing often results in unbootable VMs
- AppleScript handles complex nested configurations properly

**utm-alpine-kit uses AppleScript** in `create-alpine-template.sh` for this reason.

## Serial Console Automation

Serial console provides text-based access to VM before SSH is available.

### Why Serial Console?

During VM installation:
- ❌ SSH not available yet (not installed)
- ❌ VNC requires mouse/keyboard interaction
- ✅ Serial console provides text interface for automation

### Configuration

**UTM supports two serial console modes:**

| Mode | Purpose | Automation |
|------|---------|------------|
| **TcpServer** | Listen on localhost port | ✅ Excellent (use `nc`) |
| **Ptty** | Pseudo-terminal | ⚠️ Unreliable for scripts |

**Always use TcpServer mode for automation.**

### Setting Up Serial Console

```bash
VM_PATH="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/my-vm.utm"
CONFIG="$VM_PATH/config.plist"

# Stop UTM
osascript -e 'quit app "UTM"'
sleep 3

# Add serial console configuration
/usr/libexec/PlistBuddy -c "Add :SerialPorts array" "$CONFIG" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SerialPorts:0 dict" "$CONFIG"
/usr/libexec/PlistBuddy -c "Add :SerialPorts:0:Mode string TcpServer" "$CONFIG"
/usr/libexec/PlistBuddy -c "Add :SerialPorts:0:TcpPort integer 4444" "$CONFIG"

# Restart UTM (REQUIRED!)
open -a UTM
sleep 5

# Start VM
utmctl start my-vm

# Connect to serial console
nc localhost 4444
```

**Important:**
- Mode is case-sensitive: `TcpServer` not `tcpServer`
- Default port is 4444 (can be changed)
- UTM restart required after configuration

### Using Serial Console

**Manual connection:**
```bash
nc localhost 4444
# You're now at VM console
# Ctrl+C to exit
```

**Automation with expect:**
```tcl
#!/usr/bin/expect -f
set timeout 300

spawn nc localhost 4444

expect "login:"
send "root\r"

expect "# "
send "apk update\r"

expect "# "
send "exit\r"
```

## QEMU Guest Agent

The guest agent enables the host to communicate with running VMs.

### What It Provides

- **IP address detection** (`utmctl ip-address vm-name`)
- **Graceful shutdown** (better than power off)
- **File transfer** (if configured)
- **Time synchronization**

### Installation (Already Done in Templates)

Templates created by utm-alpine-kit already have the guest agent installed and enabled.

For manual installations:

```bash
# Install guest agent
apk add qemu-guest-agent

# Enable on boot
rc-update add qemu-guest-agent default

# Start now
rc-service qemu-guest-agent start
```

### Using Guest Agent

**Get VM IP address:**
```bash
utmctl ip-address my-vm

# Returns:
# 192.168.1.100
```

**Check if guest agent is running:**
```bash
# In VM:
rc-service qemu-guest-agent status

# On host:
utmctl ip-address my-vm
# If it returns an IP, agent is working
```

**Troubleshooting:**
```bash
# Guest agent not responding
utmctl ip-address my-vm
# (no output or error)

# SSH into VM and check:
ssh root@<vm-ip>
rc-service qemu-guest-agent status

# Restart if needed:
rc-service qemu-guest-agent restart
```

## utmctl Command Reference

**List all VMs:**
```bash
utmctl list
```

**Start VM:**
```bash
utmctl start <vm-name>
```

**Stop VM:**
```bash
utmctl stop <vm-name>
```

**Suspend VM:**
```bash
utmctl suspend <vm-name>
```

**Get VM status:**
```bash
utmctl status <vm-name>
```

**Get IP address:**
```bash
utmctl ip-address <vm-name>
```

**Clone VM:**
```bash
utmctl clone <source-vm> <new-vm>
```

**Delete VM:**
```bash
utmctl delete <vm-name>
```

**Note:** There is NO `utmctl create` - use AppleScript instead.

## VM File Structure

```
~/Library/Containers/com.utmapp.UTM/Data/Documents/
└── my-vm.utm/
    ├── config.plist          # VM configuration (XML)
    ├── Data/
    │   ├── <uuid>.qcow2     # Virtual disk image
    │   ├── efi_vars.fd      # UEFI NVRAM (ephemeral!)
    │   └── Images/          # Optional: ISO files
    └── my-vm.png            # Optional: VM icon
```

**Important notes:**
- **efi_vars.fd** - UEFI NVRAM does NOT persist reliably across UTM restarts
- **qcow2** - QEMU Copy-On-Write disk format (efficient)
- **.utm** - Bundle (directory that looks like a file in Finder)

## Networking

**utm-alpine-kit uses bridged networking:**

| Mode | Description | IP Address | Use Case |
|------|-------------|------------|----------|
| **Bridged** | VM gets IP from your network | 192.168.x.x | Production, SSH access |
| **Shared** | NAT through host | 10.0.2.x | Simple, no network setup |
| **Host-only** | Isolated network | 192.168.64.x | VM-to-VM communication |

**Why bridged?**
- VM gets real IP from your network
- SSH access from anywhere on network
- Behaves like physical machine
- Works with QEMU guest agent

**Automatic on Apple Silicon:**
- ARM Macs use bridged mode by default
- No additional configuration needed
- VMs get DHCP leases like any device

## Common Automation Patterns

### Clone and Customize

```bash
# Clone template
utmctl clone alpine-template my-test-vm

# Quit UTM
osascript -e 'quit app "UTM"'
sleep 3

# Customize resources
VM_PATH="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/my-test-vm.utm"
/usr/libexec/PlistBuddy -c "Set :Memory 4096" "$VM_PATH/config.plist"

# Restart UTM
open -a UTM
sleep 5

# Start VM
utmctl start my-test-vm

# Get IP
sleep 15  # Wait for boot
utmctl ip-address my-test-vm
```

### Serial Console Automation

```bash
# Configure serial console
VM_PATH="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/my-vm.utm"
osascript -e 'quit app "UTM"'
sleep 3

/usr/libexec/PlistBuddy -c "Add :SerialPorts:0:Mode string TcpServer" "$VM_PATH/config.plist"
/usr/libexec/PlistBuddy -c "Add :SerialPorts:0:TcpPort integer 4444" "$VM_PATH/config.plist"

open -a UTM
sleep 5

# Start and connect
utmctl start my-vm
sleep 10
echo "echo hello" | nc localhost 4444
```

## Troubleshooting

### VM config changes not applying

**Symptom:** Modified config.plist but VM still uses old settings

**Cause:** UTM configuration caching

**Solution:**
```bash
osascript -e 'quit app "UTM"'
sleep 3
open -a UTM
sleep 5
```

### Serial console not working

**Symptom:** `nc localhost 4444` fails to connect

**Causes:**
1. UTM not restarted after config change
2. Mode is case-sensitive (`TcpServer` not `tcpserver`)
3. VM not running
4. Port conflict

**Solution:**
```bash
# Verify config
/usr/libexec/PlistBuddy -c "Print :SerialPorts:0" config.plist

# Should show:
# Dict {
#     Mode = TcpServer
#     TcpPort = 4444
# }

# Restart UTM if needed
osascript -e 'quit app "UTM"' && open -a UTM
```

### Guest agent not responding

**Symptom:** `utmctl ip-address` returns nothing

**Solution:**
```bash
# Wait longer (guest agent starts after boot)
sleep 20
utmctl ip-address my-vm

# SSH in and check
ssh root@<vm-ip>
rc-service qemu-guest-agent status
rc-service qemu-guest-agent restart
```

## Further Reading

For comprehensive UTM automation knowledge:
- [UTM Automation Guide](https://gist.github.com/ChristopherA/96232f85893054b0ac4b4a04d08d8821) - Complete UTM automation patterns
- [UTM Documentation](https://docs.getutm.app/) - Official UTM guide

For utm-alpine-kit specific:
- [Template Creation](template-creation.md) - How scripts implement these patterns
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
- [Alpine Reference](alpine-reference.md) - Alpine-specific commands
