<img width="972" height="1006" alt="{2B09AAC5-1E2D-48F0-99E2-45941BB9E93C}" src="https://github.com/user-attachments/assets/ee2bdf6b-b50e-43d2-a7c0-d0e2d5facd49" />


# Cudy WR3000 OpenWrt Setup

Automated setup for Cudy WR3000 (MT7981) on OpenWrt 24.x with sing-box VPN, zapret (DPI bypass), and a web control panel.

Автоматическая настройка Cudy WR3000 (MT7981) на OpenWrt 24.x с sing-box VPN, zapret (DPI bypass) и веб-панелью управления.

## What Gets Configured / Что настраивается

- **sing-box** — two VLESS+Reality instances / два экземпляра VLESS+Reality:
  - `full_vpn` (port/порт 12345) — all traffic through VPN / весь трафик через VPN
  - `global_except_ru` (port/порт 12346) — all traffic through VPN except Russian IPs/domains / всё кроме RU через VPN
- **zapret (nfqws2)** — DPI bypass for YouTube, Discord, etc. without VPN / обход DPI для YouTube, Discord и т.д. без VPN
- **Web panel / Веб-панель** (`http://192.168.2.1/cgi-bin/vpn`) — per-device VPN and zapret control by MAC / управление VPN и zapret per-device по MAC
- **nftables tproxy** — per-device traffic routing through sing-box / маршрутизация трафика устройств через sing-box

## Prerequisites (Manual) / Предварительные шаги (ручные)

1. Flash Cudy WR3000 with OpenWrt (sysupgrade) / Прошить Cudy WR3000 OpenWrt (sysupgrade)
2. Configure networking / Настроить сеть:
   - WAN: `eth0`, DHCP (receives IP from upstream router / получает от основного роутера)
   - LAN: `br-lan` (`eth1`), static `192.168.2.1/24`
3. Ensure SSH access / Убедиться в SSH-доступе: `ssh root@192.168.2.1`
4. Attach USB drive (mounted at `/mnt/usb`) / Подключить USB-флешку (монтируется как `/mnt/usb`)
5. Verify internet connectivity / Проверить интернет: `ping 8.8.8.8`

## Installation / Установка

```sh
# On the router / На роутере
cd /tmp
# Copy the repo to the router / Скопировать репозиторий на роутер (scp, wget, etc.)
scp -r user@host:cudy-openwrt-setup /tmp/cudy-openwrt-setup

cd /tmp/cudy-openwrt-setup
sh setup.sh
```

The script will prompt for / Скрипт запросит:

| Parameter / Параметр | Description / Описание | Default / По умолчанию |
|---|---|---|
| `VLESS_SERVER` | VLESS server IP / IP VLESS-сервера | — |
| `VLESS_PORT` | Port / Порт | `42832` |
| `VLESS_UUID` | UUID | — |
| `REALITY_PUBLIC_KEY` | Reality public key / Публичный ключ Reality | — |
| `REALITY_SHORT_ID` | Short ID | — |
| `REALITY_SNI` | SNI | `www.icloud.com` |
| `WIFI_SSID` | Wi-Fi 2.4GHz SSID / Имя Wi-Fi 2.4GHz | — |
| `WIFI_PASSWORD` | Wi-Fi password / Пароль Wi-Fi | — |
| `WIFI_SSID_5G` | Wi-Fi 5GHz SSID / Имя Wi-Fi 5GHz | `{SSID}_5G` |

Parameters can also be passed as environment variables / Можно передать через переменные окружения:

```sh
VLESS_SERVER=1.2.3.4 VLESS_UUID=xxx REALITY_PUBLIC_KEY=yyy REALITY_SHORT_ID=zzz \
WIFI_SSID=MyWiFi WIFI_PASSWORD=secret sh setup.sh
```

## Repository Structure / Структура

```
├── setup.sh                          # Main setup script / Основной скрипт
├── configs/
│   ├── sing-box/                     # sing-box config templates / Шаблоны конфигов
│   ├── zapret/                       # zapret config and hostlist / Конфиг и хостлист
│   └── nftables/                     # nft table creation script / Скрипт создания таблиц
├── scripts/
│   ├── init.d/sing-box               # sing-box init.d script / init.d скрипт
│   └── cgi-bin/vpn                   # CGI web panel / CGI веб-панель
```

## Web Panel / Веб-панель

Available at / Доступна по адресу `http://192.168.2.1/cgi-bin/vpn`.

Features / Возможности:
- Toggle VPN on/off per device / Включение/выключение VPN per-device
- Toggle zapret (DPI bypass) on/off per device / Включение/выключение zapret per-device
- Select routing preset (Full VPN / Global except RU) / Выбор пресета маршрутизации
- Add/remove devices by MAC address / Добавление/удаление устройств по MAC
- Custom device naming / Именование устройств

## After Reboot / После перезагрузки

All settings are automatically restored via the `proxy-tproxy` init.d script, which:

Все настройки автоматически восстанавливаются через init.d скрипт `proxy-tproxy`, который:

- Creates nftables tables / Создаёт nftables таблицы
- Sets up ip rule/route for tproxy / Настраивает ip rule/route для tproxy
- Restores per-device rules from `/etc/vpn_state.json` / Восстанавливает per-device правила из `/etc/vpn_state.json`
