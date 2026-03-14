# vpn-zapret-openwrt-setup — Обзор проекта

## Что это
Автоматизированная настройка VPN + обход DPI (zapret) на роутерах OpenWrt с веб-панелью управления.

## Стек
- **sing-box** — VLESS-прокси (Reality и plain). Два режима на профиль: `full_vpn` (весь трафик) и `global_except_ru` (всё кроме RU)
- **zapret (nfqws2)** — обход DPI для YouTube, Discord и т.д. без VPN
- **nftables tproxy** — маршрутизация трафика на уровне устройств (по MAC-адресу)
- **CGI веб-панель** (ash shell) — управление VPN/zapret для каждого устройства
- **ash shell** — всё написано под BusyBox ash (не bash), совместимо с OpenWrt

## Архитектура маршрутизации

### Уровень 1: nftables (MAC → sing-box)
```
Пакет от устройства
  → таблица ip proxy_tproxy, chain prerouting
    → per-MAC правила: tproxy → sing-box порт (VPN ON) или accept (VPN OFF)
    → catch-all: неизвестные устройства → VPN по дефолту
```

### Уровень 2: sing-box (домены → VPN или direct)
```
sing-box получает пакет через tproxy
  → sniff определяет домен
  → route rules (первое совпадение):
    1. IP VPN-сервера → direct (избежание петли)
    2. geoip-ru / geosite-category-ru → direct (только в global_except_ru)
    3. ads rule-set → block (если adblock включён)
    4. custom rules (domain_suffix) → bypass или force-VPN
    5. default → vless-out (VPN)
```

### Уровень 3: zapret (DPI bypass)
```
Таблица inet proxy_route, chain forward_zapret
  → per-MAC: accept (zapret ON) или return (zapret OFF)
```

## Ключевые файлы

### Скрипты
| Файл | Назначение |
|------|-----------|
| `setup.sh` | Основной скрипт установки. Ставит пакеты, генерит конфиги, настраивает Wi-Fi |
| `upgrade.sh` | Скрипт обновления. AGH, адблок, DNS-миграция, шаблоны |
| `scripts/cgi-bin/vpn` | CGI веб-панель (~1090 строк ash). UI + все действия (VPN on/off, zapret, профили, custom routes) |
| `scripts/lib/generate.sh` | Shared library — общие функции для setup.sh, upgrade.sh, CGI |
| `scripts/update-rulesets.sh` | Обновление бинарных rule sets sing-box |
| `ssh_cmd.py` | Хелпер для SSH-команд на роутер с ПК |

### Шаблоны sing-box
| Файл | Назначение |
|------|-----------|
| `configs/sing-box/templates/config_full_vpn.tpl.json` | Шаблон: весь трафик через VPN |
| `configs/sing-box/templates/config_global_except_ru.tpl.json` | Шаблон: всё кроме RU через VPN |
| `configs/sing-box/rules/geoip-ru.srs` | Бинарный rule set: российские IP |
| `configs/sing-box/rules/geosite-category-ru.srs` | Бинарный rule set: российские домены |

### nftables
| Файл | Назначение |
|------|-----------|
| `configs/nftables/proxy-tproxy.sh` | Создание nft таблиц/цепочек для tproxy и zapret |

### AdGuard Home
| Файл | Назначение |
|------|-----------|
| `configs/adguardhome/AdGuardHome.yaml` | Шаблон конфига AGH |

### Конфиги на роутере (генерируются)
| Файл | Назначение |
|------|-----------|
| `/etc/vless_profiles.json` | Профили VPN (до 4 штук), порты, серверы |
| `/etc/vpn_state.json` | Состояние устройств: VPN on/off, zapret, routing, profile_id |
| `/etc/device_names.json` | Кастомные имена устройств |
| `/etc/sing-box/config_{mode}_{pid}.json` | Сгенерированные конфиги sing-box |
| `/etc/sing-box/custom_rules.json` | Кастомные bypass/force-VPN правила по доменам |
| `/etc/adguardhome.yaml` | Конфиг AGH (lowercase, стандартизирован) |
| `/etc/vpn_lan_iface` | LAN интерфейс (br-lan по дефолту) |
| `/etc/vpn_adblock` | Флаг адблока (on/off) |
| `/etc/vpn_agh_installed` | Флаг установки AGH |
| `/etc/vpn_setup_mode` | Режим установки (full/vpn-only/full-git) |
| `/etc/init.d/proxy-routing` | init.d скрипт: восстановление nft правил при перезагрузке |

## Генерация конфигов sing-box

Функция `generate_configs()` вынесена в `scripts/lib/generate.sh` (shared library):
1. Берёт шаблон `.tpl.json`
2. `sed` заменяет плейсхолдеры: `%%LISTEN_PORT%%`, `%%VLESS_SERVER%%`, `%%VLESS_UUID%%` и т.д.
3. `awk` вставляет блок security (TLS/Reality) из temp-файла вместо `%%VLESS_SECURITY_BLOCK%%`
4. `build_custom_rules_file()` генерирует кастомные правила маршрутизации
5. Результат → `/etc/sing-box/config_{mode}_{pid}.json`

## DNS-стек

```
Клиент → dnsmasq(:53, DHCP + DNS) → AGH(127.0.0.1:5354, фильтрация) → 1.1.1.1
```

- dnsmasq на :53 — обязательно (AGH на :53 ломает WiFi на MT7986)
- AGH как backend — только фильтрация рекламы
- Конфиг AGH: `/etc/adguardhome.yaml`
- IPv6 отключён (dhcpv6, ra, filter_aaaa)

## Веб-панель (CGI)

Секции UI:
1. **Profiles** — добавление/удаление VPN-профилей (vless:// URI), выбор дефолтного
2. **Add Device** — ручное добавление устройства по MAC
3. **Device List** — для каждого устройства: VPN toggle, Zapret toggle, Routing (Full VPN / Global -RU), Profile select
4. **Custom Routes** — кастомные правила обхода/принудительного VPN по доменам
5. **Adblock** — управление AdGuard Home (вкл/выкл фильтрации рекламы)

Все действия — POST/GET → обработка → 302 redirect → обновлённая страница.

## Варианты установки (setup.sh)

| Режим | Что ставится | Размер |
|-------|-------------|--------|
| `full` (default) | VPN + zapret (tarball) | ~18 MB |
| `vpn-only` | Только VPN, без zapret | ~15 MB |
| `full-git` | VPN + zapret (git clone) | ~48 MB |
