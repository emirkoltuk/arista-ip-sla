#!/bin/bash

#############################################
# ZAMAN AYARLARI VE EŞİKLER
#############################################
PingInterval=5           # saniye
FailureThreshold=5       # art arda başarısız ping -> DOWN
SuccessThreshold=2       # art arda başarılı ping -> UP

#############################################
# HEDEF IP’LER (reachability test)
#############################################
SITE1_DEST_IP="192.0.2.10"     
SITE2_DEST_IP="198.51.100.20" 

#############################################
# ARAYÜZ ve NEXT-HOP’LAR
#############################################
INTERFACE="ethX"                 # Gerçek interface yerine generic
PRIMARY_NEXT_HOP="203.0.113.1"   # Örnek IP (RFC5737)
BACKUP_NEXT_HOP="203.0.113.2"    # Örnek IP (RFC5737)

#############################################
# LOG
#############################################
LOGFILE="/path/to/RouteTrack.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"; }

#############################################
# LİSTE DOSYALARI (hot-reload)
#############################################
SITE1_LIST_FILE="/path/to/site1_networks.txt"
SITE2_LIST_FILE="/path/to/site2_networks.txt"

# Dahili durum sayaçları/flag’lar
SITE1_HOSTUP=Y
SITE2_HOSTUP=Y
SITE1_FailureCount=0
SITE1_SuccessCount=0
SITE2_FailureCount=0
SITE2_SuccessCount=0

# Periyodik senkron (dosya değişmese de)
RECONCILE_EVERY="${RECONCILE_EVERY:-3600}"  # saniye
RECON_COUNTER=0

#############################################
# Yardımcı Fonksiyonlar
#############################################

# Liste dosyalarını oku (boş/yorum satırlarını atla)
read_lists() {
    mapfile -t NETWORK_SITE1_LIST < <(grep -Ev '^\s*($|#)' "$SITE1_LIST_FILE" 2>/dev/null || true)
    mapfile -t NETWORK_SITE2_LIST < <(grep -Ev '^\s*($|#)' "$SITE2_LIST_FILE"    2>/dev/null || true)
}

# Dosyalar değişti mi tespit et (md5 yoksa wc -c ile)
lists_checksum() {
    if command -v md5sum >/dev/null 2>&1; then
        {
            md5sum "$SITE1_LIST_FILE" 2>/dev/null
            md5sum "$SITE2_LIST_FILE" 2>/dev/null
        } | awk '{print $1}' | tr '\n' ' '
    else
        {
            wc -c "$SITE1_LIST_FILE" 2>/dev/null
            wc -c "$SITE2_LIST_FILE" 2>/dev/null
        } | awk '{print $1}' | tr '\n' ' '
    fi
}

# Verilen network listesine göre state=UP/DOWN ise rotaları idempotent push/sil
ensure_routes_state() {
    # $1: state (UP/DOWN), $2: array ref
    local state="$1"; shift
    local -n NETS="$1"

    if [ "$state" = "UP" ]; then
        for NETWORK in "${NETS[@]}"; do
            (
                echo enable
                echo configure terminal
                echo ip route $NETWORK $PRIMARY_NEXT_HOP
            ) | FastCli -p 15 -A -M
        done
    else
        for NETWORK in "${NETS[@]}"; do
            (
                echo enable
                echo configure terminal
                echo no ip route $NETWORK $PRIMARY_NEXT_HOP
            ) | FastCli -p 15 -A -M
        done
    fi
}

#############################################
# Başlangıç: listeleri yükle ve hash al
#############################################
read_lists
LISTS_HASH="$(lists_checksum)"
log "Network listeleri yüklendi. SITE1: ${#NETWORK_SITE1_LIST[@]} adet, SITE2: ${#NETWORK_SITE2_LIST[@]} adet."

#############################################
# Ana Döngü
#############################################
while true; do
    ########################
    # SITE1 reachability
    ########################
    if ping -I "$INTERFACE" -c 1 -W 2 "$SITE1_DEST_IP" &>/dev/null; then
        SITE1_FailureCount=0
        SITE1_SuccessCount=$((SITE1_SuccessCount + 1))

        if [ "$SITE1_HOSTUP" = "N" ] && [ $SITE1_SuccessCount -ge $SuccessThreshold ]; then
            log "SITE1 SUCCESS - primary route restored"
            ensure_routes_state UP NETWORK_SITE1_LIST
            SITE1_HOSTUP=Y
            SITE1_SuccessCount=0
        else
            [ "$SITE1_HOSTUP" = "Y" ] && [ $SITE1_SuccessCount -eq 1 ] && log "SITE1 SUCCESS"
        fi
    else
        SITE1_SuccessCount=0
        SITE1_FailureCount=$((SITE1_FailureCount + 1))

        if [ $SITE1_FailureCount -ge $FailureThreshold ] && [ "$SITE1_HOSTUP" = "Y" ]; then
            log "SITE1 FAIL - switching to backup route (primary routes removed)"
            ensure_routes_state DOWN NETWORK_SITE1_LIST
            SITE1_HOSTUP=N
            SITE1_FailureCount=0
        else
            log "SITE1 ping fail detected ($SITE1_FailureCount/$FailureThreshold)"
        fi
    fi

    ########################
    # SITE2 reachability
    ########################
    if ping -I "$INTERFACE" -c 1 -W 2 "$SITE2_DEST_IP" &>/dev/null; then
        SITE2_FailureCount=0
        SITE2_SuccessCount=$((SITE2_SuccessCount + 1))

        if [ "$SITE2_HOSTUP" = "N" ] && [ $SITE2_SuccessCount -ge $SuccessThreshold ]; then
            log "SITE2 SUCCESS - primary route restored"
            ensure_routes_state UP NETWORK_SITE2_LIST
            SITE2_HOSTUP=Y
            SITE2_SuccessCount=0
        else
            [ "$SITE2_HOSTUP" = "Y" ] && [ $SITE2_SuccessCount -eq 1 ] && log "SITE2 SUCCESS"
        fi
    else
        SITE2_SuccessCount=0
        SITE2_FailureCount=$((SITE2_FailureCount + 1))

        if [ $SITE2_FailureCount -ge $FailureThreshold ] && [ "$SITE2_HOSTUP" = "Y" ]; then
            log "SITE2 FAIL - switching to backup route (primary routes removed)"
            ensure_routes_state DOWN NETWORK_SITE2_LIST
            SITE2_HOSTUP=N
            SITE2_FailureCount=0
        else
            log "SITE2 ping fail detected ($SITE2_FailureCount/$FailureThreshold)"
        fi
    fi

    ########################
    # Hot-reload: Liste değiştiyse anında senkron
    ########################
    NEW_HASH="$(lists_checksum)"
    if [ "$NEW_HASH" != "$LISTS_HASH" ]; then
        read_lists
        LISTS_HASH="$NEW_HASH"
        log "Liste dosyalarında değişiklik algılandı; mevcut duruma göre senkronize ediliyor."
        [ "$SITE1_HOSTUP" = "Y" ] && ensure_routes_state UP   NETWORK_SITE1_LIST || ensure_routes_state DOWN NETWORK_SITE1_LIST
        [ "$SITE2_HOSTUP" = "Y" ] && ensure_routes_state UP   NETWORK_SITE2_LIST || ensure_routes_state DOWN NETWORK_SITE2_LIST
        log "Network listeleri güncellendi. SITE1: ${#NETWORK_SITE1_LIST[@]} adet, SITE2: ${#NETWORK_SITE2_LIST[@]} adet."
    fi

    ########################
    # Periyodik senkron (opsiyonel)
    ########################
    RECON_COUNTER=$((RECON_COUNTER + PingInterval))
    if [ "$RECONCILE_EVERY" -gt 0 ] && [ $RECON_COUNTER -ge $RECONCILE_EVERY ]; then
        RECON_COUNTER=0
        [ "$SITE1_HOSTUP" = "Y" ] && ensure_routes_state UP   NETWORK_SITE1_LIST || ensure_routes_state DOWN NETWORK_SITE1_LIST
        [ "$SITE2_HOSTUP" = "Y" ] && ensure_routes_state UP   NETWORK_SITE2_LIST || ensure_routes_state DOWN NETWORK_SITE2_LIST
        log "Periyodik route senkronizasyonu tamamlandı."
    fi

    sleep "$PingInterval"
done
