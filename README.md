# RouteTrack Script for Arista (FastCli Based)

## Overview
This script monitors the reachability of two remote sites (**SITE1** and **SITE2**) using ICMP ping.  
If a site's primary destination IP becomes unreachable for a configured threshold, the script automatically removes the static routes associated with that site from the Arista switch/router using `FastCli`.  
When the site becomes reachable again, the static routes are restored.

It also supports **hot-reload** of route lists from external files without restarting the script.

---

## Features
- Monitors two independent remote destinations (`SITE1` and `SITE2`)
- Automatic route removal/restore based on reachability
- Hot-reload of network lists without restart
- Periodic resynchronization of routes
- Detailed logging of events

---

## Requirements
- **Arista EOS** with `FastCli` available
- Bash shell support
- `ping` command available
- Optional: `md5sum` for list change detection (falls back to `wc -c` if unavailable)

---

## Configuration

Edit the script variables according to your environment:

```bash
# Ping and threshold settings
PingInterval=5           # seconds between checks
FailureThreshold=5       # consecutive ping fails before marking DOWN
SuccessThreshold=2       # consecutive successes before marking UP

# Destination IPs
SITE1_DEST_IP="192.0.2.10"     # Example IP (RFC5737)
SITE2_DEST_IP="198.51.100.20"  # Example IP (RFC5737)

# Interface and next-hops
INTERFACE="ethX"               # Interface used for ping
PRIMARY_NEXT_HOP="203.0.113.1" # Primary next hop
BACKUP_NEXT_HOP="203.0.113.2"  # Backup next hop (optional)

# Log file location
LOGFILE="/path/to/RouteTrack.log"

# Network list files
SITE1_LIST_FILE="/path/to/site1_networks.txt"
SITE2_LIST_FILE="/path/to/site2_networks.txt"
