# 8GB RAM Optimizations for Raspberry Pi 4

## Overview

Your Raspberry Pi 4 with 8GB RAM is well-equipped for demanding tasks. This configuration optimizes the system to take full advantage of the available memory.

## Memory Configuration Highlights

### Swap Strategy
- **Default**: No swap enabled (8GB is usually sufficient)
- **Optional**: 2-4GB swapfile available on btrfs @swap subvolume
- **Use cases for swap**:
  - Large Nix builds (e.g., compiling from source)
  - Memory-intensive applications
  - Emergency OOM protection
  - Hibernation support (if needed)

### Kernel Memory Management
```nix
boot.kernel.sysctl = {
  # Use more RAM for file system cache
  "vm.vfs_cache_pressure" = 50;        # Default: 100
  "vm.dirty_ratio" = 15;               # Default: 20
  "vm.dirty_background_ratio" = 5;     # Default: 10
  
  # Btrfs-specific optimizations
  "vm.dirty_expire_centisecs" = 3000;  # 30 seconds
  "vm.dirty_writeback_centisecs" = 500; # 5 seconds
  
  # Better memory management
  "vm.swappiness" = 10;                # Prefer RAM over swap
  "vm.min_free_kbytes" = 131072;       # 128MB reserved
  "vm.page-cluster" = 3;               # More aggressive read-ahead
};
```

## Performance Benefits

### File System Caching
- **50% more aggressive caching** (`vfs_cache_pressure = 50`)
- **Larger file cache** utilizes available RAM effectively
- **Better read performance** for frequently accessed files

### Network Performance
- **128MB network buffers** for better throughput
- **Optimized TCP windows** for modern networks
- **Better handling** of concurrent connections

### Btrfs Optimizations
- **Longer commit intervals** reduce SSD wear
- **Better memory utilization** for metadata
- **Improved compression performance** with more RAM

## Monitoring Memory Usage

### Quick Commands
```bash
# Overall memory usage
free -h
htop

# Detailed breakdown
cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Cached|Buffers)"

# Btrfs memory usage
sudo btrfs filesystem show
sudo btrfs filesystem usage /
```

### Memory Breakdown Typical for 8GB System
```
MemTotal:     8GB
MemFree:      2-4GB (varies with workload)
MemAvailable: 5-7GB (includes reclaimable cache)
Cached:       1-3GB (file system cache)
Buffers:      100-500MB (I/O buffers)
```

## Workload-Specific Optimizations

### For Development/Building
```bash
# Enable swap temporarily for large builds
sudo swapon /swap/swapfile  # If configured

# Monitor during builds
watch -n 1 'free -h && echo "=== Top Memory Users ===" && ps aux --sort=-%mem | head -10'
```

### For Server Workloads
- **More file cache**: Excellent for file servers
- **Better network performance**: Good for web services
- **Stable under load**: 8GB provides good headroom

### For Desktop Use
- **Smooth multitasking**: Can run many applications
- **Better browser performance**: More tabs without swapping
- **Faster application launches**: More caching

## Tuning Guidelines

### When to Enable Swap
Enable if you experience:
```bash
# Check for OOM events
dmesg | grep -i "killed process"
journalctl | grep -i "out of memory"

# Monitor memory pressure
cat /proc/pressure/memory
```

### Memory Pressure Monitoring
```bash
# Set up memory monitoring
echo 'some 1000000' > /sys/fs/cgroup/memory.events
# Monitor for memory.events changes
```

## Troubleshooting

### High Memory Usage
```bash
# Find memory hogs
sudo ps aux --sort=-%mem | head -20
sudo systemd-cgtop

# Check for memory leaks
sudo smem -t
```

### Performance Issues
```bash
# Check if swap is being used (bad sign with 8GB)
swapon --show
cat /proc/swaps

# Verify kernel parameters are applied
sysctl vm.vfs_cache_pressure
sysctl vm.dirty_ratio
sysctl vm.min_free_kbytes
```

## Recommended Packages for 8GB System

With 8GB RAM, you can comfortably run:
- **Development environments** (VSCode, IDEs)
- **Containers** (Docker, Podman)
- **Databases** (PostgreSQL, MariaDB)
- **Web servers** (Nginx, Apache)
- **Build systems** (Nix, compilation)
- **Desktop environments** (if using GUI)

## Memory Usage Expectations

| Scenario | RAM Usage | Available |
|----------|-----------|-----------|
| Minimal system | 0.5-1GB | 7-7.5GB |
| Desktop environment | 1-2GB | 6-7GB |
| Development setup | 2-3GB | 5-6GB |
| Heavy workload | 4-6GB | 2-4GB |

The configuration ensures optimal performance across all these scenarios while protecting against memory exhaustion.
