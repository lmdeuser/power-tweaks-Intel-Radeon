# power-tweaks-Intel-Radeon
Этот набор скриптов и systemd-юнитов автоматически управляет энергопотреблением ноутбука с гибридной графикой (Intel CPU + Radeon dGPU). В отличие от TLP, проект интегрируется с современным power-profiles-daemon и не создаёт конфликтов с GNOME

✨ Возможности

✅ Автоматическое переключение между режимами питания при подключении/отключении зарядки

✅ Интеграция с power-profiles-daemon (power-saver на батарее, balanced на сети)

✅ Оптимизация CPU (powersave/performance governor)

✅ Управление dGPU Radeon (авто-отключение на батарее)

✅ SATA ALPM с безопасными настройками для SSD + btrfs

✅ Wi-Fi power save автоматическое управление

✅ PCIe ASPM настройки

✅ Звуковая карта энергосбережение

✅ USB autosuspend по TLP-рецепту

✅ NMI Watchdog отключение на батарее

✅ VM dirty page оптимизация

✅ Режимы сна (deep на батарее, s2idle на сети)

💻 Требования

ОС: Fedora 40+ (протестировано на Fedora 43)

Ноутбук: с Intel CPU и дискретной графикой Radeonpower-tweaks-hybrid-gpu/
├── install.sh                 # Скрипт установки
├── uninstall.sh              # Скрипт удаления
├── switch-ppd-profile.sh     # Основной скрипт тюнинга
├── power-profile-monitor.sh  # DBus монитор для PPD
├── power-tweaks.service      # Systemd oneshot сервис
├── power-tweaks.path         # Path монитор для AC статуса
├── power-tweaks.timer        # Периодическая проверка
├── power-profile-monitor.service # DBus монитор сервис
├── 99-power-tweaks.rules     # Udev правило
├── README.md                 # Этот файл
├── CHANGELOG.md              # История изменений
└── LICENSE                   # Лицензия MIT

🔧 Как это работает
Архитектура системы
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Udev rule     │────▶│  power-tweaks   │◀────│  Path monitor   │
│  (plug/unplug)  │     │    service      │     │  (AC изменеия)   │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Timer (2 min)  │────▶│  switch-ppd-    │◀────│  DBus monitor   │
│   подстраховка  │     │  profile.sh     │     │  (PPD смена)    │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  Применение настроек:   │
                    │  • CPU governor         │
                    │  • SATA ALPM            │
                    │  • dGPU control         │
                    │  • Wi-Fi power save     │
                    │  • Режимы сна           │
                    │  • И другое...          │
                    └─────────────────────────┘

 
                  Логика переключения режимов
Режим	AC статус	PPD профиль	CPU governor	SATA ALPM	Режим сна
Батарея	offline	power-saver	powersave	med_power_with_dipm	deep (если доступен)
Сеть	online	balanced	performance	max_performance	s2idle
✅ Проверка работы
# Статус всех сервисов
systemctl status power-tweaks.{service,path,timer}
systemctl status power-profile-monitor.service

# Логи
sudo journalctl -u power-tweaks.service -f

# Текущий режим
cat /sys/class/power_supply/AC/online
powerprofilesctl get

# Мониторинг udev событий
sudo udevadm monitor --property --subsystem-match=power_supply

# Проверка применённых настроек
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/class/scsi_host/host0/link_power_management_policy
cat /sys/power/mem_sleep
🗑️ Удаление
# Запустить скрипт удаления
sudo ./uninstall.sh

# Или вручную:
sudo systemctl disable --now power-tweaks.{service,path,timer} power-profile-monitor.service
sudo rm /etc/systemd/system/power-tweaks.*
sudo rm /etc/systemd/system/power-profile-monitor.service
sudo rm /usr/local/sbin/switch-ppd-profile.sh
sudo rm /usr/local/sbin/power-profile-monitor.sh
sudo rm /etc/udev/rules.d/99-power-tweaks.rules
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
🔍 Диагностика
Проблемы и решения
Проблема	Возможное решение
Скрипт не запускается при смене питания	sudo udevadm control --reload-rules && sudo udevadm trigger
PPD не переключается	Проверить systemctl status power-profiles-daemon
Логи пустые	sudo journalctl -u power-tweaks.service -f
dGPU не отключается	Проверить lspci | grep Radeon и исправить PCI адрес в скрипте

Настройка под своё железо
Если у вас другая модель ноутбука, отредактируйте PCI адрес dGPU в скрипте:
# Найдите свой GPU
lspci | grep -E "VGA|3D|Radeon"

# Исправьте в switch-ppd-profile.sh строку с 0000:01:00.0

# Все логи
journalctl -t power-tweaks

# В реальном времени
sudo journalctl -t power-tweaks -f

# Только ошибки
journalctl -t power-tweaks -p err





Пакеты:

power-profiles-daemon

iw (для Wi-Fi)

systemd

📁 Структура файлов
