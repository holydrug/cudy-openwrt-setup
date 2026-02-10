#!/bin/sh
# Update sing-box geoip/geosite rule sets from SagerNet GitHub
# Designed to run via cron (weekly): 0 4 * * 1 /etc/sing-box/update-rulesets.sh
# Downloads directly (not through VPN)

RULES_DIR="/etc/sing-box/rules"
GEOIP_URL="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs"
GEOSITE_URL="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs"
MIN_SIZE=500

log() { logger -t update-rulesets "$1"; }

download_rule() {
    local url="$1" dest="$2" name="$3"
    local tmp="${dest}.tmp"

    curl -sL --connect-timeout 15 --max-time 60 -o "$tmp" "$url" 2>/dev/null
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to download $name"
        rm -f "$tmp"
        return 1
    fi

    local size=$(wc -c < "$tmp" | tr -d ' ')
    if [ "$size" -lt "$MIN_SIZE" ]; then
        log "ERROR: $name too small (${size} bytes), keeping old version"
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$dest"
    log "OK: Updated $name (${size} bytes)"
    return 0
}

mkdir -p "$RULES_DIR"

updated=0
download_rule "$GEOIP_URL" "$RULES_DIR/geoip-ru.srs" "geoip-ru" && updated=1
download_rule "$GEOSITE_URL" "$RULES_DIR/geosite-category-ru.srs" "geosite-category-ru" && updated=1

if [ "$updated" -eq 1 ]; then
    log "Rule sets updated, restarting sing-box..."
    /etc/init.d/sing-box restart 2>/dev/null
fi

log "Update check complete"
