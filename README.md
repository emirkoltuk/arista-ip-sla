# RouteTrack Script for Arista EOS

## Overview
RouteTrack is a Bash script designed for **Arista EOS** to automatically manage **primary and backup static routes** based on reachability tests.  
The script:
- Continuously monitors two remote destinations (**SITE1** and **SITE2**) using ICMP ping.
- If the **primary route** fails, it removes the primary static route entry and relies on the **secondary (backup) route** configured with **metric 50**.
- When the primary destination becomes reachable again, it **re-adds** the primary route.
- Supports **hot-reloading** of network lists from files without restarting the script.
- Can be set to start automatically on device boot via **Event-Handler**.

---

## Features
- **Primary/Secondary Route Management**: Primary route has lower metric (preferred), secondary route has metric 50.
- **Automatic Failover**: On primary failure, primary route is removed; backup route takes over.
- **Automatic Recovery**: On primary recovery, the primary route is re-added.
- **Hot-Reload**: Updates route lists on file change without restarting the script.
- **Logging**: Tracks state changes and actions taken.
- **Startup Automation**: Integrated with Arista’s Event-Handler to run at boot.

---

## Network Topology Example
```
[ Arista EOS Switch ]
         |
         +--- Primary Next-Hop (metric 0)
         |
         +--- Backup Next-Hop (metric 50)
```

---

## Static Route Configuration
On the Arista device, static routes should be configured so that the **primary route** is preferred and the **backup route** has `metric 50`.  
Example:
```plaintext
ip route 192.0.2.0/24 203.0.113.1      # Primary
ip route 192.0.2.0/24 203.0.113.2 50   # Secondary (metric 50)
```

When the script detects primary failure:
- The primary route is removed (`no ip route` command).
- Backup route (metric 50) automatically takes over.
- On recovery, the primary route is re-added.

---

## Example Prefix-List for BGP Redistribution
```plaintext
ip prefix-list STATIC-TO-BGP seq 10 permit 192.0.2.0/24
ip prefix-list STATIC-TO-BGP seq 20 permit 192.0.3.0/24
```

---

## Installation on Arista EOS

### 1. Upload the Script
Copy `routetrack.sh` to the persistent storage:
```bash
scp routetrack.sh admin@<switch-ip>:/mnt/flash/
```

### 2. Set Execution Permissions
```bash
chmod +x /mnt/flash/routetrack.sh
```

### 3. Create Network List Files
Example:
```bash
echo "192.0.2.0/24" > /mnt/flash/site1_networks.txt
echo "198.51.100.0/24" > /mnt/flash/site2_networks.txt
```

### 4. Configure Event-Handler
Add the following to the running config to start the script at boot:
```plaintext
event-handler RouteTrack
   trigger on-boot
   action bash /mnt/flash/routetrack.sh
   delay 10
   asynchronous
```
You can also configure a second script if needed:
```plaintext
event-handler RouteTrack2
   trigger on-boot
   action bash /mnt/flash/routetrack2.sh
   delay 10
```

---

## Logging
Events are logged to the file specified in `LOGFILE`:
```plaintext
2025-08-12 14:05:10 - SITE1 ping fail detected (1/5)
2025-08-12 14:05:15 - SITE1 FAIL - switching to backup route (primary routes removed)
2025-08-12 14:05:30 - SITE1 SUCCESS - primary route restored
```

---

## Parameters
| Variable             | Description |
|----------------------|-------------|
| `PingInterval`       | Interval between reachability checks (seconds) |
| `FailureThreshold`   | Number of consecutive failures before marking site DOWN |
| `SuccessThreshold`   | Number of consecutive successes before marking site UP |
| `PRIMARY_NEXT_HOP`   | Next-hop IP for primary route |
| `BACKUP_NEXT_HOP`    | Next-hop IP for backup route |
| `SITE1_DEST_IP`      | Destination IP to monitor for Site 1 |
| `SITE2_DEST_IP`      | Destination IP to monitor for Site 2 |
| `LOGFILE`            | Path to log file |
| `SITE1_LIST_FILE`    | File containing Site 1 prefixes |
| `SITE2_LIST_FILE`    | File containing Site 2 prefixes |

---

## Example Boot Configuration
```plaintext
ip virtual-router mac-address 00:0c:29:00:fb:fb
ip routing
!
ip route 192.0.2.0/24 203.0.113.1
ip route 192.0.2.0/24 203.0.113.2 50
```

---

## License
MIT License – free to use, modify, and distribute.

---

## Disclaimer
This script modifies routing configuration.  
**Always test in a lab environment before deploying to production.**
