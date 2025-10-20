# Troubleshooting Guide

Solutions for common issues with Alpine VM Manager.

## Template Creation Issues

### Serial Console Timeout

**Symptom:** Script hangs waiting for serial console connection

```
Waiting for serial console...
(hangs indefinitely)
```

**Cause:** UTM configuration not reloaded after setting TcpServer mode

**Solution:**

```bash
# 1. Verify serial console is configured
cd ~/Library/Containers/com.utmapp.UTM/Data/Documents/alpine-template.utm
/usr/libexec/PlistBuddy -c "Print :SerialPort:0" config.plist

# Should output:
# Dict {
#     Mode = TcpServer
#     TcpPort = 4444
# }

# 2. If correct but still failing, manually restart UTM
killall UTM
sleep 3
open -a UTM
sleep 5

# 3. Restart VM
utmctl start alpine-template

# 4. Test serial console
nc localhost 4444
# Should connect to Alpine console
```

**Prevention:** The script automatically restarts UTM. If issues persist, check UTM isn't being auto-launched by macOS.

### Serial Console Case Sensitivity

**Symptom:** Serial console configured but not accessible

**Cause:** PlistBuddy is case-sensitive. `TcpServer` not `tcpServer` or `TCP`.

**Solution:**

```bash
# Check current value
/usr/libexec/PlistBuddy -c "Print :SerialPort:0:Mode" config.plist

# If wrong, delete and recreate
/usr/libexec/PlistBuddy -c "Delete :SerialPort:0" config.plist
/usr/libexec/PlistBuddy -c "Add :SerialPort:0:Mode string TcpServer" config.plist
/usr/libexec/PlistBuddy -c "Add :SerialPort:0:TcpPort integer 4444" config.plist

# Restart UTM
killall UTM && sleep 3 && open -a UTM
```

### HTTP Server Port Conflict

**Symptom:**

```
Error: Failed to start HTTP server on port 8888
Port already in use
```

**Cause:** Another process using port 8888

**Solution:**

```bash
# Find process using port 8888
lsof -i :8888

# Kill it
kill $(lsof -t -i :8888)

# Or use a different port (requires script modification)
# Edit create-alpine-template.sh, change HTTP_PORT=8888 to HTTP_PORT=8889
```

**Prevention:** The script checks for port availability before starting. If you see this error, a process started between the check and server launch.

### Answer File Not Found (404)

**Symptom:** Alpine installation fails with "Could not download answer file"

**Cause:** HTTP server not serving correct directory

**Solution:**

```bash
# Check HTTP server is running
ps aux | grep "python3 -m http.server"

# Check answer file exists
ls -la templates/alpine-template.answers

# Test HTTP server manually
curl http://localhost:8888/alpine-template.answers

# Should output the answer file content
# If 404, check you're in the correct directory
pwd  # Should be in utm-alpine-kit/
```

### DISKOPTS Not Executing

**Symptom:** Alpine installed but not on disk, still boots from ISO

**Cause:** Alpine answer file quirk - `DISKOPTS` sets mode but doesn't run `setup-disk`

**Solution:** This is expected. The script explicitly calls `setup-disk` via `lib/install-disk.exp` after the answer file completes.

**Verification:**

```bash
# Check disk was partitioned
utmctl start alpine-template
sleep 10
ssh -i ~/.ssh/id_ed25519_alpine_vm root@<IP> "df -h"

# Should show /dev/vda1 mounted on /boot
# Should show /dev/vda2 mounted on /
```

### Password Not Set

**Symptom:** Cannot login with password in UTM console

**Cause:** Answer files cannot set passwords directly

**Solution:** The script sets password via SSH after installation:

```bash
# Manual password set
utmctl start alpine-template
VM_IP=$(utmctl ip-address alpine-template | head -1)
ssh -i ~/.ssh/id_ed25519_alpine_vm root@$VM_IP "echo 'root:alpine' | chpasswd"
```

**Alternative:** Use SSH keys exclusively (recommended)

## VM Cloning Issues

### Clone Hangs or Fails

**Symptom:**

```
Cloning VM (this may take 10-30 seconds)...
(hangs for minutes)
```

**Cause:** Template VM is running

**Solution:**

```bash
# Stop template first
utmctl stop alpine-template

# Wait for full shutdown
sleep 3

# Retry clone
./scripts/clone-vm.sh test-vm-1
```

**Prevention:** The script checks and stops template automatically, but UTM may take time to fully stop the VM.

### MAC Address Conflicts

**Symptom:** Cloned VM gets same IP as template or another VM

**Cause:** MAC address not changed, DHCP server recognizes it as same device

**Solution:**

```bash
# The script automatically generates new MACs
# Verify it worked:
cd ~/Library/Containers/com.utmapp.UTM/Data/Documents/test-vm-1.utm
/usr/libexec/PlistBuddy -c "Print :Network:0:MacAddress" config.plist

# Should show different MAC than template
cd ~/Library/Containers/com.utmapp.UTM/Data/Documents/alpine-template.utm
/usr/libexec/PlistBuddy -c "Print :Network:0:MacAddress" config.plist
```

**Manual fix:**

```bash
# Generate new MAC
NEW_MAC=$(printf '52:54:00:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))

# Set it
/usr/libexec/PlistBuddy -c "Set :Network:0:MacAddress $NEW_MAC" config.plist

# Restart UTM
killall UTM && sleep 3 && open -a UTM
```

### UTM Configuration Not Updating

**Symptom:** Changed RAM/CPU but VM still uses old values

**Cause:** UTM caches VM configurations in memory

**Solution:**

```bash
# Always quit UTM before modifying config.plist
osascript -e 'quit app "UTM"'
sleep 2

# Make changes with PlistBuddy
/usr/libexec/PlistBuddy -c "Set :System:MemorySize 2048" config.plist

# Restart UTM
open -a UTM
sleep 3

# Verify change
/usr/libexec/PlistBuddy -c "Print :System:MemorySize" config.plist
```

**Critical:** Never modify config.plist while UTM is running. Changes will be overwritten.

## Network and Connectivity Issues

### No IP Address Detected

**Symptom:**

```
Detecting IP address via QEMU guest agent...
(times out after 20 seconds)
Could not auto-detect IP address
```

**Causes and Solutions:**

**1. QEMU guest agent not running**

```bash
# SSH into VM (use UTM console to find IP)
ssh -i ~/.ssh/id_ed25519_alpine_vm root@<IP>

# Check if installed
apk info qemu-guest-agent

# If not installed
apk add qemu-guest-agent
rc-update add qemu-guest-agent default
rc-service qemu-guest-agent start
```

**2. VM still booting**

```bash
# Just wait longer (up to 30 seconds for slow systems)
# Or manually check
utmctl status alpine-template
# Wait until status shows "started" for 10+ seconds
```

**3. Manual IP detection**

```bash
# Option A: Via UTM console
# Open UTM, click VM, click Console
# Login and run: ip addr show eth0

# Option B: Via router DHCP table
# Check your router's DHCP leases for MAC address

# Option C: Via network scan
nmap -sn 192.168.1.0/24 | grep -B 2 "52:54:00"
```

### SSH Connection Refused

**Symptom:**

```bash
ssh -i ~/.ssh/id_ed25519_alpine_vm root@192.168.1.100
ssh: connect to host 192.168.1.100 port 22: Connection refused
```

**Causes and Solutions:**

**1. sshd not running**

```bash
# Via UTM console
login: root
# (enter password if set, or should auto-login with key)

# Check sshd status
rc-service sshd status

# Start if stopped
rc-service sshd start

# Enable at boot
rc-update add sshd default
```

**2. Wrong IP address**

```bash
# Verify IP
ip addr show eth0

# Or via QEMU guest agent
utmctl ip-address <vm-name>
```

**3. Firewall blocking**

```bash
# Check iptables rules
iptables -L -n

# Temporarily flush rules (for testing)
iptables -F

# Allow SSH permanently
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
```

### SSH Permission Denied (publickey)

**Symptom:**

```bash
ssh -i ~/.ssh/id_ed25519_alpine_vm root@192.168.1.100
Permission denied (publickey)
```

**Causes and Solutions:**

**1. Wrong SSH key**

```bash
# Verify key exists
ls -la ~/.ssh/id_ed25519_alpine_vm

# Check key was deployed to VM
ssh root@192.168.1.100 "cat /root/.ssh/authorized_keys"
# Should show your public key
```

**2. Key not in answer file**

```bash
# Check answer file
cat templates/alpine-template.answers | grep ROOTSSHKEY

# Should show: ROOTSSHKEY="%%SSH_KEY%%"
# Or your actual key if you modified it
```

**3. Permissions wrong**

```bash
# On macOS
chmod 600 ~/.ssh/id_ed25519_alpine_vm

# In VM (via console)
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
```

## Provisioning Issues

### Package Installation Fails

**Symptom:**

```bash
apk add python3
ERROR: unable to select packages:
  python3 (no such package)
```

**Cause:** APK cache not updated

**Solution:**

```bash
# Always update first
apk update
apk add python3

# Or one-liner
apk add --update-cache python3
```

### Language Detection Fails

**Symptom:** `provision-for-testing.sh` doesn't install language dependencies

**Cause:** Repository doesn't have standard dependency files

**Solution:**

```bash
# Install manually after cloning
ssh -i ~/.ssh/id_ed25519_alpine_vm root@<IP>
cd /root/testing/<repo>

# Python
apk add python3 py3-pip
pip3 install -r requirements.txt

# Node.js
apk add nodejs npm
npm install

# Go
apk add go
go mod download

# Rust
apk add rust cargo
cargo fetch
```

### Tests Fail on Alpine

**Symptom:** Tests pass on Ubuntu but fail on Alpine

**Causes:**

1. **musl libc vs glibc** - Some binaries compiled for glibc don't work
2. **BusyBox utilities** - Different flags than GNU coreutils
3. **Missing dependencies** - Alpine has minimal base

**Solutions:**

```bash
# Install GNU coreutils if needed
apk add coreutils

# Check for glibc dependencies
ldd /path/to/binary
# If it requires glibc, it won't work natively

# Install compatibility layer (not recommended for production)
apk add gcompat
```

## Performance Issues

### VM Boot Slow

**Symptom:** VM takes >30 seconds to boot

**Causes:**

1. **Not enough resources** - Increase RAM/CPU
2. **Disk I/O bottleneck** - Use SSD for VM storage
3. **Too many VMs** - Reduce concurrent VMs

**Solutions:**

```bash
# Increase resources for specific VM
./scripts/clone-vm.sh fast-vm --ram 2 --cpu 4

# Check disk speed
dd if=/dev/zero of=/root/test bs=1M count=100
# Should be >100 MB/s on SSD

# Check host resources
vm_stat
top
```

### Clone Very Slow

**Symptom:** Clone takes >60 seconds

**Cause:** Large template size or slow disk

**Solutions:**

```bash
# Check template size
du -sh ~/Library/Containers/com.utmapp.UTM/Data/Documents/alpine-template.utm
# Should be <2GB for minimal template

# Reduce template size
# 1. Remove package cache
apk cache clean

# 2. Remove unnecessary packages
apk del <package>

# 3. Clean logs
rm -f /var/log/*.log
```

## UTM-Specific Issues

### UTM Won't Start

**Symptom:** `open -a UTM` fails silently

**Solution:**

```bash
# Check if already running
ps aux | grep UTM

# Force kill if frozen
killall -9 UTM
sleep 2

# Try launching again
open -a UTM

# Check Console.app for UTM crash logs
open -a Console
```

### utmctl Command Not Found

**Symptom:**

```bash
utmctl list
zsh: command not found: utmctl
```

**Solution:**

```bash
# Create symlink
sudo ln -sf /Applications/UTM.app/Contents/MacOS/utmctl /usr/local/bin/utmctl

# Or use full path
/Applications/UTM.app/Contents/MacOS/utmctl list

# Add to PATH in ~/.zshrc
export PATH="/Applications/UTM.app/Contents/MacOS:$PATH"
```

### VM Bundle Corrupted

**Symptom:** VM won't start, UTM shows errors

**Solution:**

```bash
# 1. Try to delete via utmctl
utmctl delete <vm-name>

# 2. If that fails, delete manually
rm -rf ~/Library/Containers/com.utmapp.UTM/Data/Documents/<vm-name>.utm

# 3. Restart UTM
killall UTM
open -a UTM

# 4. Recreate VM from template
./scripts/clone-vm.sh <vm-name>
```

## Script Issues

### Script Permission Denied

**Symptom:**

```bash
./scripts/create-alpine-template.sh
zsh: permission denied: ./scripts/create-alpine-template.sh
```

**Solution:**

```bash
# Make executable
chmod +x scripts/*.sh
chmod +x scripts/lib/*.exp

# Or run with bash
bash scripts/create-alpine-template.sh
```

### expect Not Found

**Symptom:**

```
./scripts/lib/install-via-answerfile.exp: line 1: expect: command not found
```

**Solution:**

```bash
# Install expect
brew install expect

# Verify installation
which expect
# Should output: /usr/local/bin/expect (or /opt/homebrew/bin/expect)
```

## Getting Help

If you encounter an issue not covered here:

1. **Check logs:**
   ```bash
   # Script logs (if --verbose used)
   cat /tmp/alpine-template-creation.log

   # UTM logs
   ~/Library/Containers/com.utmapp.UTM/Data/Library/Logs/
   ```

2. **Search existing issues:**
   https://github.com/ChristopherA/utm-alpine-kit/issues

3. **Ask in discussions:**
   https://github.com/ChristopherA/utm-alpine-kit/discussions

4. **Report a bug:**
   https://github.com/ChristopherA/utm-alpine-kit/issues/new

When reporting issues, include:
- macOS version
- UTM version
- Script output (full, not truncated)
- Relevant error messages
- Steps to reproduce
