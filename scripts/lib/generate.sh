#!/bin/sh
# Shared library: config generation, profile helpers, adblock placeholder handling
# Sourced by: CGI panel, setup.sh, upgrade.sh

# Requires PROFILES_FILE, TEMPLATES_DIR, CUSTOM_RULES_FILE to be set by caller

# ===== Profile helpers =====

get_all_servers() {
    grep -o '"server":"[^"]*"' "$PROFILES_FILE" | sed 's/"server":"//;s/"//' | sort -u | tr '\n' ',' | sed 's/,$//'
}

get_default_profile_id() {
    grep -o '"default_profile_id":"[^"]*"' "$PROFILES_FILE" | head -1 | sed 's/.*"default_profile_id":"//;s/"//'
}

get_profile_port() {
    local pid="$1" mode="$2"
    local key
    case "$mode" in
        full_vpn) key="port_full_vpn" ;;
        *) key="port_global_except_ru" ;;
    esac
    grep -o "\"id\":\"$pid\"[^}]*" "$PROFILES_FILE" | grep -o "\"$key\":[0-9]*" | head -1 | sed "s/\"$key\"://"
}

get_profile_field() {
    local pid="$1" field="$2"
    grep -o "\"id\":\"$pid\"[^}]*" "$PROFILES_FILE" | grep -o "\"$field\":\"[^\"]*\"" | head -1 | sed "s/\"$field\":\"//;s/\"//"
}

get_profile_ids() {
    grep -o '"id":"[^"]*"' "$PROFILES_FILE" | sed 's/"id":"//;s/"//'
}

# ===== Custom rules builder =====

_filter_domains() {
    echo "$1" | tr ',' '\n' | grep -vE '^"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | tr '\n' ',' | sed 's/,$//'
}

_filter_ips() {
    echo "$1" | tr ',' '\n' | grep -E '^"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | tr '\n' ',' | sed 's/,$//'
}

build_custom_rules_file() {
    local mode="$1" route_out="$2" dns_out="$3"
    local rules_file="$CUSTOM_RULES_FILE"
    > "$route_out"; > "$dns_out"
    [ -f "$rules_file" ] || return 0

    local direct=$(grep -o '"direct":\[[^]]*\]' "$rules_file" | sed 's/"direct":\[//;s/\]$//' | tr -d ' ')
    local vpn=$(grep -o '"vpn":\[[^]]*\]' "$rules_file" | sed 's/"vpn":\[//;s/\]$//' | tr -d ' ')

    local direct_domains=$(_filter_domains "$direct")
    local direct_ips=$(_filter_ips "$direct")
    local vpn_domains=$(_filter_domains "$vpn")
    local vpn_ips=$(_filter_ips "$vpn")

    case "$mode" in
        global_except_ru)
            [ -n "$direct_domains" ] && {
                echo "      {\"domain_suffix\":[$direct_domains],\"outbound\":\"direct\"}," >> "$route_out"
                echo "      {\"domain_suffix\":[$direct_domains],\"server\":\"dns-direct\"}," >> "$dns_out"
            } || true
            [ -n "$direct_ips" ] && {
                echo "      {\"ip_cidr\":[$direct_ips],\"outbound\":\"direct\"}," >> "$route_out"
            } || true
            [ -n "$vpn_domains" ] && {
                echo "      {\"domain_suffix\":[$vpn_domains],\"outbound\":\"vless-out\"}," >> "$route_out"
                echo "      {\"domain_suffix\":[$vpn_domains],\"server\":\"dns-remote\"}," >> "$dns_out"
            } || true
            [ -n "$vpn_ips" ] && {
                echo "      {\"ip_cidr\":[$vpn_ips],\"outbound\":\"vless-out\"}," >> "$route_out"
            } || true
            ;;
        full_vpn)
            [ -n "$direct_domains" ] && {
                echo "      ,{\"domain_suffix\":[$direct_domains],\"outbound\":\"direct\"}" >> "$route_out"
                echo "      ,{\"domain_suffix\":[$direct_domains],\"server\":\"dns-direct\"}" >> "$dns_out"
            } || true
            [ -n "$direct_ips" ] && {
                echo "      ,{\"ip_cidr\":[$direct_ips],\"outbound\":\"direct\"}" >> "$route_out"
            } || true
            ;;
    esac
}

# ===== Adblock placeholder expansion =====

_build_adblock_files() {
    local mode="$1"
    local ab_dns_server="/tmp/sb_ab_dns_server_$$"
    local ab_dns_rule="/tmp/sb_ab_dns_rule_$$"
    local ab_block_out="/tmp/sb_ab_block_out_$$"
    local ab_route_rule="/tmp/sb_ab_route_rule_$$"
    local ab_rule_set_section="/tmp/sb_ab_rule_set_section_$$"
    local ab_rule_set_entry="/tmp/sb_ab_rule_set_entry_$$"

    local adblock_on="0"
    [ -f /etc/vpn_adblock ] && adblock_on=$(cat /etc/vpn_adblock 2>/dev/null) || true
    local srs_exists="0"
    [ -f /etc/sing-box/rules/geosite-category-ads-all.srs ] && srs_exists="1"

    if [ "$adblock_on" = "1" ] && [ "$srs_exists" = "1" ]; then
        # DNS server: block ads with rcode://success (inline append, same for both templates)
        printf ',{"tag":"dns-block","address":"rcode://success"}' > "$ab_dns_server"
        # Block outbound (inline append, same for both templates)
        printf ',{"type":"block","tag":"block"}' > "$ab_block_out"

        # DNS rule and route rule differ per template:
        # - full_vpn: inline on same line (leading comma, no trailing comma)
        # - global_except_ru: own line (no leading comma, trailing comma)
        if [ "$mode" = "full_vpn" ]; then
            printf ',{"rule_set":"geosite-category-ads-all","server":"dns-block"}' > "$ab_dns_rule"
            printf ',{"rule_set":"geosite-category-ads-all","outbound":"block"}' > "$ab_route_rule"
        else
            printf '      {"rule_set":"geosite-category-ads-all","server":"dns-block"},\n' > "$ab_dns_rule"
            printf '      {"rule_set":"geosite-category-ads-all","outbound":"block"},\n' > "$ab_route_rule"
        fi

        if [ "$mode" = "full_vpn" ]; then
            # Full rule_set section (full_vpn has no existing rule_set)
            cat > "$ab_rule_set_section" << 'RSETEOF'
,
    "rule_set": [
      {
        "type": "local",
        "tag": "geosite-category-ads-all",
        "format": "binary",
        "path": "/etc/sing-box/rules/geosite-category-ads-all.srs"
      }
    ],
RSETEOF
        else
            printf '' > "$ab_rule_set_section"
        fi

        if [ "$mode" = "global_except_ru" ]; then
            # Single entry to append to existing rule_set array
            cat > "$ab_rule_set_entry" << 'RSENTEOF'
,
      {
        "type": "local",
        "tag": "geosite-category-ads-all",
        "format": "binary",
        "path": "/etc/sing-box/rules/geosite-category-ads-all.srs"
      }
RSENTEOF
        else
            printf '' > "$ab_rule_set_entry"
        fi
    else
        # Adblock OFF or rule-set missing: all empty (except rule_set_section needs comma)
        printf '' > "$ab_dns_server"
        printf '' > "$ab_dns_rule"
        printf '' > "$ab_block_out"
        printf '' > "$ab_route_rule"
        printf ',' > "$ab_rule_set_section"
        printf '' > "$ab_rule_set_entry"
    fi
}

_cleanup_adblock_files() {
    rm -f "/tmp/sb_ab_dns_server_$$" "/tmp/sb_ab_dns_rule_$$" \
          "/tmp/sb_ab_block_out_$$" "/tmp/sb_ab_route_rule_$$" \
          "/tmp/sb_ab_rule_set_section_$$" "/tmp/sb_ab_rule_set_entry_$$"
}

# ===== Config generation =====

generate_configs() {
    local pid="$1" port_full="$2" port_global="$3"
    local server="$4" server_port="$5" uuid="$6"
    local pbk="$7" sid="$8" sni="$9"
    shift 9
    local fp="$1" flow="$2" security="$3"

    # Build security block (flow + tls) or empty for security=none
    local sec_file="/tmp/sb_sec_block_$$"
    if [ "$security" = "none" ]; then
        printf '' > "$sec_file"
    else
        cat > "$sec_file" << SECEOF
,
      "flow": "$flow",
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "utls": {
          "enabled": true,
          "fingerprint": "$fp"
        },
        "reality": {
          "enabled": true,
          "public_key": "$pbk",
          "short_id": "$sid"
        }
      }
SECEOF
    fi

    for mode in full_vpn global_except_ru; do
        local tpl="$TEMPLATES_DIR/config_${mode}.tpl.json"
        [ -f "$tpl" ] || continue
        local listen_port
        case "$mode" in
            full_vpn) listen_port="$port_full" ;;
            *) listen_port="$port_global" ;;
        esac

        local cr_route="/tmp/sb_custom_route_$$"
        local cr_dns="/tmp/sb_custom_dns_$$"
        build_custom_rules_file "$mode" "$cr_route" "$cr_dns"

        # Build adblock placeholder files
        _build_adblock_files "$mode"

        local ab_dns_server="/tmp/sb_ab_dns_server_$$"
        local ab_dns_rule="/tmp/sb_ab_dns_rule_$$"
        local ab_block_out="/tmp/sb_ab_block_out_$$"
        local ab_route_rule="/tmp/sb_ab_route_rule_$$"
        local ab_rule_set_section="/tmp/sb_ab_rule_set_section_$$"
        local ab_rule_set_entry="/tmp/sb_ab_rule_set_entry_$$"

        sed \
            -e "s|%%LISTEN_PORT%%|$listen_port|g" \
            -e "s|%%PROFILE_ID%%|$pid|g" \
            -e "s|%%VLESS_SERVER%%|$server|g" \
            -e "s|%%VLESS_PORT%%|$server_port|g" \
            -e "s|%%VLESS_UUID%%|$uuid|g" \
            "$tpl" | awk \
                -v secfile="$sec_file" \
                -v crroute="$cr_route" \
                -v crdns="$cr_dns" \
                -v abdns="$ab_dns_server" \
                -v abdnsrule="$ab_dns_rule" \
                -v abblock="$ab_block_out" \
                -v abroute="$ab_route_rule" \
                -v abrset="$ab_rule_set_section" \
                -v abrentry="$ab_rule_set_entry" '
            /%%VLESS_SECURITY_BLOCK%%/ {
                gsub(/%%VLESS_SECURITY_BLOCK%%/, "")
                printf "%s", $0
                while ((getline line < secfile) > 0) print line
                close(secfile)
                next
            }
            /%%CUSTOM_ROUTE_RULES%%/ {
                while ((getline line < crroute) > 0) print line
                close(crroute)
                next
            }
            /%%CUSTOM_DNS_RULES%%/ {
                while ((getline line < crdns) > 0) print line
                close(crdns)
                next
            }
            /%%ADBLOCK_DNS_SERVER%%/ {
                gsub(/%%ADBLOCK_DNS_SERVER%%/, "")
                printf "%s", $0
                while ((getline line < abdns) > 0) printf "%s", line
                close(abdns)
                printf "\n"
                next
            }
            /%%ADBLOCK_DNS_RULE%%/ {
                gsub(/%%ADBLOCK_DNS_RULE%%/, "")
                printf "%s", $0
                while ((getline line < abdnsrule) > 0) printf "%s", line
                close(abdnsrule)
                printf "\n"
                next
            }
            /%%ADBLOCK_BLOCK_OUTBOUND%%/ {
                gsub(/%%ADBLOCK_BLOCK_OUTBOUND%%/, "")
                printf "%s", $0
                while ((getline line < abblock) > 0) printf "%s", line
                close(abblock)
                printf "\n"
                next
            }
            /%%ADBLOCK_ROUTE_RULE%%/ {
                gsub(/%%ADBLOCK_ROUTE_RULE%%/, "")
                printf "%s", $0
                while ((getline line < abroute) > 0) printf "%s", line
                close(abroute)
                printf "\n"
                next
            }
            /%%ADBLOCK_RULE_SET_SECTION%%/ {
                gsub(/%%ADBLOCK_RULE_SET_SECTION%%/, "")
                printf "%s", $0
                while ((getline line < abrset) > 0) print line
                close(abrset)
                next
            }
            /%%ADBLOCK_RULE_SET_ENTRY%%/ {
                gsub(/%%ADBLOCK_RULE_SET_ENTRY%%/, "")
                printf "%s", $0
                while ((getline line < abrentry) > 0) print line
                close(abrentry)
                printf "\n"
                next
            }
            { print }
            ' > "/etc/sing-box/config_${mode}_${pid}.json"
        rm -f "$cr_route" "$cr_dns"
        _cleanup_adblock_files
    done
    rm -f "$sec_file"
}

# ===== Xray-core config generation =====

generate_xray_configs() {
    local pid="$1" port_full="$2" port_global="$3"
    local server="$4" server_port="$5" uuid="$6"
    local pbk="$7" sid="$8" sni="$9"
    shift 9
    local fp="$1" flow="$2" security="$3"
    local transport="${4:-tcp}" transport_mode="${5:-auto}" transport_path="${6:-/}"

    mkdir -p /etc/xray

    # Build flow field
    local flow_json=""
    [ -n "$flow" ] && flow_json=",\"flow\":\"$flow\""

    # Build transport settings
    local transport_block=""
    case "$transport" in
        xhttp)
            transport_block="\"network\":\"xhttp\",\"xhttpSettings\":{\"mode\":\"${transport_mode}\",\"path\":\"${transport_path}\"}"
            ;;
        ws)
            transport_block="\"network\":\"ws\",\"wsSettings\":{\"path\":\"${transport_path}\"}"
            ;;
        *)
            transport_block="\"network\":\"tcp\""
            ;;
    esac

    # Build security settings
    local security_block=""
    case "$security" in
        reality)
            security_block=",\"security\":\"reality\",\"realitySettings\":{\"serverName\":\"$sni\",\"fingerprint\":\"$fp\",\"publicKey\":\"$pbk\",\"shortId\":\"$sid\"}"
            ;;
        *)
            security_block=",\"security\":\"none\""
            ;;
    esac

    # Adblock rules
    local adblock_rules="" adblock_outbound=""
    local adblock_on="0"
    [ -f /etc/vpn_adblock ] && adblock_on=$(cat /etc/vpn_adblock 2>/dev/null)
    if [ "$adblock_on" = "1" ]; then
        adblock_rules=",{\"type\":\"field\",\"domain\":[\"geosite:category-ads-all\"],\"outboundTag\":\"block\"}"
        adblock_outbound=",{\"tag\":\"block\",\"protocol\":\"blackhole\",\"settings\":{}}"
    fi

    # Custom domain + IP rules
    local custom_rules=""
    if [ -f "$CUSTOM_RULES_FILE" ]; then
        local direct_raw=$(grep -o '"direct":\[[^]]*\]' "$CUSTOM_RULES_FILE" | sed 's/"direct":\[//;s/\]$//' | tr -d ' ')
        local vpn_raw=$(grep -o '"vpn":\[[^]]*\]' "$CUSTOM_RULES_FILE" | sed 's/"vpn":\[//;s/\]$//' | tr -d ' ')
        if [ -n "$direct_raw" ]; then
            local xd=$(echo "$direct_raw" | sed 's/"//g' | tr ',' '\n' | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | awk 'NF {printf "\"domain:%s\",", $0}' | sed 's/,$//')
            local xdi=$(echo "$direct_raw" | sed 's/"//g' | tr ',' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | awk 'NF {printf "\"%s\",", $0}' | sed 's/,$//')
            [ -n "$xd" ] && custom_rules="${custom_rules},{\"type\":\"field\",\"domain\":[${xd}],\"outboundTag\":\"direct\"}"
            [ -n "$xdi" ] && custom_rules="${custom_rules},{\"type\":\"field\",\"ip\":[${xdi}],\"outboundTag\":\"direct\"}"
        fi
        if [ -n "$vpn_raw" ]; then
            local xv=$(echo "$vpn_raw" | sed 's/"//g' | tr ',' '\n' | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | awk 'NF {printf "\"domain:%s\",", $0}' | sed 's/,$//')
            local xvi=$(echo "$vpn_raw" | sed 's/"//g' | tr ',' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | awk 'NF {printf "\"%s\",", $0}' | sed 's/,$//')
            [ -n "$xv" ] && custom_rules="${custom_rules},{\"type\":\"field\",\"domain\":[${xv}],\"outboundTag\":\"vless-out\"}"
            [ -n "$xvi" ] && custom_rules="${custom_rules},{\"type\":\"field\",\"ip\":[${xvi}],\"outboundTag\":\"vless-out\"}"
        fi
    fi

    for mode in full_vpn global_except_ru; do
        local listen_port
        case "$mode" in
            full_vpn) listen_port="$port_full" ;;
            *) listen_port="$port_global" ;;
        esac

        local geo_rules=""
        if [ "$mode" = "global_except_ru" ]; then
            geo_rules=",{\"type\":\"field\",\"domain\":[\"geosite:category-ru\"],\"outboundTag\":\"direct\"},{\"type\":\"field\",\"ip\":[\"geoip:ru\"],\"outboundTag\":\"direct\"}"
        fi

        cat > "/etc/xray/config_${mode}_${pid}.json" << XRAYEOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[{
    "tag":"tproxy-in",
    "protocol":"dokodemo-door",
    "port":${listen_port},
    "listen":"::",
    "settings":{"network":"tcp,udp","followRedirect":true},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]},
    "streamSettings":{"sockopt":{"tproxy":"tproxy"}}
  }],
  "outbounds":[
    {"tag":"vless-out","protocol":"vless","settings":{"vnext":[{"address":"${server}","port":${server_port},"users":[{"id":"${uuid}","encryption":"none"${flow_json}}]}]},"streamSettings":{${transport_block}${security_block}}},
    {"tag":"direct","protocol":"freedom","settings":{}}${adblock_outbound}
  ],
  "routing":{
    "domainStrategy":"AsIs",
    "rules":[
      {"type":"field","ip":["${server}"],"outboundTag":"direct"}${adblock_rules}${custom_rules}${geo_rules}
    ]
  }
}
XRAYEOF
    done
}

# ===== Regenerate all configs =====

regenerate_all_configs() {
    get_profile_ids | while read pid; do
        local server=$(get_profile_field "$pid" "server")
        local server_port=$(grep -o "\"id\":\"$pid\"[^}]*" "$PROFILES_FILE" | grep -o '"server_port":[0-9]*' | head -1 | sed 's/"server_port"://')
        local uuid=$(get_profile_field "$pid" "uuid")
        local pbk=$(get_profile_field "$pid" "public_key")
        local sid=$(get_profile_field "$pid" "short_id")
        local sni=$(get_profile_field "$pid" "sni")
        local fp=$(get_profile_field "$pid" "fingerprint")
        local flow=$(get_profile_field "$pid" "flow")
        local security=$(get_profile_field "$pid" "security")
        local port_full=$(get_profile_port "$pid" "full_vpn")
        local port_global=$(get_profile_port "$pid" "global_except_ru")
        local engine=$(get_profile_field "$pid" "engine")
        [ -z "$engine" ] && engine="sing-box"

        case "$engine" in
            xray)
                local transport=$(get_profile_field "$pid" "transport")
                local transport_mode=$(get_profile_field "$pid" "transport_mode")
                local transport_path=$(get_profile_field "$pid" "transport_path")
                generate_xray_configs "$pid" "$port_full" "$port_global" \
                    "$server" "$server_port" "$uuid" "$pbk" "$sid" "$sni" \
                    "$fp" "$flow" "$security" "$transport" "$transport_mode" "$transport_path"
                ;;
            *)
                generate_configs "$pid" "$port_full" "$port_global" \
                    "$server" "$server_port" "$uuid" "$pbk" "$sid" "$sni" "$fp" "$flow" "$security"
                ;;
        esac
    done || true
    /etc/init.d/sing-box restart 2>/dev/null || true
    /etc/init.d/xray-core restart 2>/dev/null || true
}
