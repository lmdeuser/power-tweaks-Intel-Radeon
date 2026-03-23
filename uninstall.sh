#!/usr/bin/env bash
# Скрипт удаления power-tweaks
# Запускать: sudo bash uninstall-power-tweaks.sh

set -e

echo "========================================="
echo "Удаление power-tweaks"
echo "========================================="

# Останавливаем и отключаем сервисы
echo "→ Останавливаем сервисы..."
systemctl stop power-tweaks.{service,path,timer} 2>/dev/null || true
systemctl stop power-profile-monitor.service 2>/dev/null || true

echo "→ Отключаем сервисы..."
systemctl disable power-tweaks.{service,path,timer} 2>/dev/null || true
systemctl disable power-profile-monitor.service 2>/dev/null || true

# Удаляем файлы
echo "→ Удаляем файлы..."
rm -f /usr/local/sbin/switch-ppd-profile.sh
rm -f /usr/local/sbin/power-profile-monitor.sh
rm -f /etc/systemd/system/power-tweaks.*
rm -f /etc/systemd/system/power-profile-monitor.service
rm -f /etc/udev/rules.d/99-power-tweaks.rules

# Перезагружаем конфигурацию
echo "→ Перезагружаем конфигурацию..."
systemctl daemon-reload
udevadm control --reload-rules

echo "========================================="
echo "✅ Power-tweaks успешно удален"
echo "========================================="
