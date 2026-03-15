#!/usr/bin/env bash
# Полная установка power-tweaks для ноутбуков с Intel CPU + Radeon dGPU
# Запускать: sudo bash install-power-tweaks.sh

set -e  # Прерывать при ошибке

echo "========================================="
echo "Установка power-tweaks для Intel + Radeon"
echo "========================================="

# Создаем директории если их нет
mkdir -p /usr/local/sbin

# 1. ОСНОВНОЙ СКРИПТ
echo "→ Создаю /usr/local/sbin/switch-ppd-profile.sh"
cat > /usr/local/sbin/switch-ppd-profile.sh << 'EOF'
#!/usr/bin/env bash
# power-tweaks.sh — для ноутбуков с Intel CPU + Radeon dGPU
# Fedora, power-profiles-daemon, гибридная графика
# Автоматическое переключение: battery → power-saver, ac → balanced

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | systemd-cat -t power-tweaks
    echo -e "${GREEN}→${NC} $*" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | systemd-cat -t power-tweaks -p err
    echo -e "${RED}✗${NC} $*" >&2
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | systemd-cat -t power-tweaks -p warning
    echo -e "${YELLOW}⚠${NC} $*" >&2
}

# Проверка наличия powerprofilesctl
if ! command -v powerprofilesctl &> /dev/null; then
    warn "powerprofilesctl не найден, использую только AC статус"
    PPD_AVAILABLE=0
else
    PPD_AVAILABLE=1
fi

# ────────────────────────────────────────────────
# Определяем режим по статусу AC
# ────────────────────────────────────────────────
AC_PATH="/sys/class/power_supply/AC/online"
if [ -f "$AC_PATH" ]; then
    AC_ONLINE=$(cat "$AC_PATH" 2>/dev/null || echo "1")
else
    # Альтернативные пути для разных ноутбуков
    AC_PATH="/sys/class/power_supply/ACAD/online"
    if [ -f "$AC_PATH" ]; then
        AC_ONLINE=$(cat "$AC_PATH" 2>/dev/null || echo "1")
    else
        AC_ONLINE="1"
        warn "AC path не найден, предполагаем сетевое питание"
    fi
fi

if [ $PPD_AVAILABLE -eq 1 ]; then
    CURRENT_PPD=$(powerprofilesctl get 2>/dev/null || echo "unknown")
else
    CURRENT_PPD="unavailable"
fi

if [[ "$AC_ONLINE" == "0" ]]; then
    MODE="battery"
else
    MODE="ac"
fi

log "Режим питания: $MODE (AC: $AC_ONLINE, текущий PPD: $CURRENT_PPD)"

# ────────────────────────────────────────────────
# АВТОМАТИЧЕСКОЕ ПЕРЕКЛЮЧЕНИЕ PPD
# ────────────────────────────────────────────────
if [ $PPD_AVAILABLE -eq 1 ]; then
    TARGET_PPD=""
    case "$MODE" in
        battery)
            TARGET_PPD="power-saver"
            ;;
        ac)
            TARGET_PPD="balanced"
            ;;
    esac
    
    if [ -n "$TARGET_PPD" ] && [ "$CURRENT_PPD" != "$TARGET_PPD" ]; then
        log "Переключаю PPD с '$CURRENT_PPD' на '$TARGET_PPD'"
        if powerprofilesctl set "$TARGET_PPD" 2>/dev/null; then
            log "✓ PPD успешно переключен на $TARGET_PPD"
            CURRENT_PPD="$TARGET_PPD"
        else
            warn "Не удалось переключить PPD на $TARGET_PPD"
        fi
    else
        log "PPD уже в правильном режиме: $CURRENT_PPD"
    fi
fi

# ────────────────────────────────────────────────
# Поиск PCI адреса Radeon GPU
# ────────────────────────────────────────────────
RADEON_PCI=""
if command -v lspci &> /dev/null; then
    RADEON_PCI=$(lspci | grep -i "Radeon" | cut -d' ' -f1)
    if [ -n "$RADEON_PCI" ]; then
        # Добавляем префикс 0000: и приводим к формату
        RADEON_PCI="0000:$(echo "$RADEON_PCI" | sed 's/:/::/')"
        log "Найден Radeon GPU: $RADEON_PCI"
    else
        warn "Radeon GPU не найден"
    fi
fi

# ────────────────────────────────────────────────
# Поиск Wi-Fi интерфейса
# ────────────────────────────────────────────────
WIFI_IFACE=""
if command -v iw &> /dev/null; then
    WIFI_IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
    if [ -n "$WIFI_IFACE" ]; then
        log "Найден Wi-Fi интерфейс: $WIFI_IFACE"
    fi
fi

# ────────────────────────────────────────────────
# Применяем настройки в зависимости от режима
# ────────────────────────────────────────────────
case "$MODE" in
    battery)
        log "BATTERY MODE: применяем энергосберегающие настройки"
        
        # CPU Governor
        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            echo "powersave" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || warn "Не удалось установить CPU governor"
            log "  CPU governor: powersave"
        else
            warn "CPU governor интерфейс не найден"
        fi
        
        # Energy Performance Preference
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
            echo "power" | tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference >/dev/null 2>&1 || true
            log "  CPU EPP: power"
        fi
        
        # PCIe ASPM
        echo "auto" | tee /sys/bus/pci/devices/*/power/control >/dev/null 2>&1 || true
        log "  PCIe ASPM: auto"
        
        # dGPU Radeon
        if [ -n "$RADEON_PCI" ] && [ -e "/sys/bus/pci/devices/$RADEON_PCI/power/control" ]; then
            echo "auto" > "/sys/bus/pci/devices/$RADEON_PCI/power/control" 2>/dev/null && \
                log "  dGPU: динамическое управление" || warn "dGPU не поддерживает динамическое управление"
        fi
        
        # Wi-Fi power save
        if [ -n "$WIFI_IFACE" ]; then
            if iw dev "$WIFI_IFACE" set power_save on 2>/dev/null; then
                log "  Wi-Fi ($WIFI_IFACE): power save ON"
            else
                warn "Wi-Fi power save не включен"
            fi
        fi
        
        # SATA ALPM для SSD - безопасный режим
        log "  SATA ALPM:"
        for h in /sys/class/scsi_host/host*/link_power_management_policy; do
            if [ -w "$h" ]; then
                echo "med_power_with_dipm" > "$h" 2>/dev/null && \
                    log "    ✓ $(basename $(dirname "$h")): med_power_with_dipm"
            fi
        done
        
        # Звуковая карта
        if [ -w /sys/module/snd_hda_intel/parameters/power_save ]; then
            echo 1 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
            echo 10 > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true
            log "  Звук: энергосбережение включено"
        fi
        
        # USB
        if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
            echo 0 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null || true
            log "  USB: autosuspend отключен"
        fi
        
        # NMI Watchdog
        if [ -w /proc/sys/kernel/nmi_watchdog ]; then
            echo 0 > /proc/sys/kernel/nmi_watchdog 2>/dev/null || true
            log "  NMI Watchdog: отключен"
        fi
        
        # VM dirty page parameters
        if [ -w /proc/sys/vm/dirty_writeback_centisecs ]; then
            echo 500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || true
            log "  VM dirty_writeback: 5 секунд"
        fi
        
        # Режим сна - deep если доступен
        if grep -q "deep" /sys/power/mem_sleep 2>/dev/null; then
            echo "deep" > /sys/power/mem_sleep 2>/dev/null && log "  Режим сна: deep (S3)"
        else
            log "  Режим сна: s2idle (deep не поддерживается)"
        fi
        ;;
        
    ac)
        log "AC MODE: применяем настройки производительности"
        
        # CPU Governor
        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || warn "Не удалось установить CPU governor"
            log "  CPU governor: performance"
        fi
        
        # Energy Performance Preference
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
            echo "balance_performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference >/dev/null 2>&1 || true
            log "  CPU EPP: balance_performance"
        fi
        
        # PCIe
        echo "on" | tee /sys/bus/pci/devices/*/power/control >/dev/null 2>&1 || true
        log "  PCIe: всегда включено"
        
        # Wi-Fi
        if [ -n "$WIFI_IFACE" ]; then
            if iw dev "$WIFI_IFACE" set power_save off 2>/dev/null; then
                log "  Wi-Fi ($WIFI_IFACE): power save OFF"
            else
                warn "Wi-Fi power save не отключен"
            fi
        fi
        
        # SATA
        log "  SATA: max_performance"
        for h in /sys/class/scsi_host/host*/link_power_management_policy; do
            if [ -w "$h" ]; then
                echo "max_performance" > "$h" 2>/dev/null || true
            fi
        done
        
        # Звук
        if [ -w /sys/module/snd_hda_intel/parameters/power_save ]; then
            echo 0 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
            echo "N" > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true
            log "  Звук: энергосбережение отключено"
        fi
        
        # USB
        if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
            echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null || true
            log "  USB: autosuspend отключен"
        fi
        
        # NMI Watchdog
        if [ -w /proc/sys/kernel/nmi_watchdog ]; then
            echo 1 > /proc/sys/kernel/nmi_watchdog 2>/dev/null || true
            log "  NMI Watchdog: включен"
        fi
        
        # VM parameters
        if [ -w /proc/sys/vm/dirty_writeback_centisecs ]; then
            echo 5000 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || true
            log "  VM dirty_writeback: 50 секунд"
        fi
        
        # Режим сна - s2idle
        echo "s2idle" > /sys/power/mem_sleep 2>/dev/null && log "  Режим сна: s2idle"
        ;;
esac

# ────────────────────────────────────────────────
# Финальный отчет
# ────────────────────────────────────────────────
log "✓ Все настройки применены успешно"
if [ $PPD_AVAILABLE -eq 1 ]; then
    FINAL_PPD=$(powerprofilesctl get 2>/dev/null)
    log "Финальный профиль PPD: $FINAL_PPD"
fi

exit 0
EOF

# Делаем скрипт исполняемым
chmod +x /usr/local/sbin/switch-ppd-profile.sh
echo "  ✓ Готово"

# 2. SYSTEMD SERVICE
echo "→ Создаю /etc/systemd/system/power-tweaks.service"
cat > /etc/systemd/system/power-tweaks.service << 'EOF'
[Unit]
Description=Apply power tweaks for Intel + Radeon laptops
After=power-profiles-daemon.service
Before=multi-user.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/switch-ppd-profile.sh
StandardOutput=journal
StandardError=journal
User=root
Group=root
RemainAfterExit=yes
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ Готово"

# 3. SYSTEMD PATH MONITOR
echo "→ Создаю /etc/systemd/system/power-tweaks.path"
cat > /etc/systemd/system/power-tweaks.path << 'EOF'
[Unit]
Description=Monitor AC power status changes for power tweaks

[Path]
PathModified=/sys/class/power_supply/AC/online
Unit=power-tweaks.service

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ Готово"

# 4. SYSTEMD TIMER
echo "→ Создаю /etc/systemd/system/power-tweaks.timer"
cat > /etc/systemd/system/power-tweaks.timer << 'EOF'
[Unit]
Description=Periodic power tweaks check
Requires=power-tweaks.service

[Timer]
OnCalendar=*:0/2
OnBootSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
echo "  ✓ Готово"

# 5. DBUS MONITOR SERVICE
echo "→ Создаю /etc/systemd/system/power-profile-monitor.service"
cat > /etc/systemd/system/power-profile-monitor.service << 'EOF'
[Unit]
Description=Monitor power profile changes and apply tweaks
After=power-profiles-daemon.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/power-profile-monitor.sh
Restart=always
RestartSec=1
User=root

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ Готово"

# 6. DBUS MONITOR SCRIPT
echo "→ Создаю /usr/local/sbin/power-profile-monitor.sh"
cat > /usr/local/sbin/power-profile-monitor.sh << 'EOF'
#!/usr/bin/env bash
# Мониторинг смены профиля питания через dbus

dbus-monitor --system "interface='org.freedesktop.portal.Settings',member=SettingChanged" | while read -r line; do
    if echo "$line" | grep -q "PowerProfile"; then
        /usr/local/sbin/switch-ppd-profile.sh
    fi
done
EOF

chmod +x /usr/local/sbin/power-profile-monitor.sh
echo "  ✓ Готово"

# 7. UDEV RULE
echo "→ Создаю /etc/udev/rules.d/99-power-tweaks.rules"
cat > /etc/udev/rules.d/99-power-tweaks.rules << 'EOF'
SUBSYSTEM=="power_supply", KERNEL=="AC", ACTION=="change", RUN+="/usr/local/sbin/switch-ppd-profile.sh"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/local/sbin/switch-ppd-profile.sh"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/local/sbin/switch-ppd-profile.sh"
EOF
echo "  ✓ Готово"

echo "========================================="
echo "Активация всех компонентов..."
echo "========================================="

# Перезагружаем systemd
systemctl daemon-reload

# Активируем сервисы
systemctl enable power-tweaks.service
systemctl start power-tweaks.service

systemctl enable power-tweaks.path
systemctl start power-tweaks.path

systemctl enable power-tweaks.timer
systemctl start power-tweaks.timer

systemctl enable power-profile-monitor.service
systemctl start power-profile-monitor.service

# Перезагружаем udev
udevadm control --reload-rules
udevadm trigger --subsystem-match=power_supply

echo "========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "========================================="
echo ""
echo "Проверка статуса:"
systemctl status power-tweaks.service --no-pager | head -5
echo ""
echo "Просмотр логов:"
echo "  sudo journalctl -u power-tweaks.service -f"
echo ""
echo "Для удаления используйте отдельный скрипт:"
echo "  curl -fsSL https://github.com/lmdeuser/power-tweaks-Intel-Radeon/blob/main/uninstall.sh | sudo bash"
echo "========================================="
