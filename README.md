# power-tweaks-Intel-Radeon

Набор скриптов и systemd-юнитов для автоматического управления энергопотреблением ноутбука с гибридной графикой (Intel CPU + Radeon dGPU). В отличие от TLP, проект интегрируется с современным `power-profiles-daemon` и не создаёт конфликтов с GNOME.

## ✨ Возможности

- ✅ Автоматическое переключение между режимами питания при подключении/отключении зарядки
- ✅ Интеграция с `power-profiles-daemon` (power-saver на батарее, balanced на сети)
- ✅ Оптимизация CPU (powersave/performance governor)
- ✅ Управление dGPU Radeon (авто-отключение на батарее)
- ✅ SATA ALPM с безопасными настройками для SSD + btrfs
- ✅ Wi-Fi power save автоматическое управление
- ✅ PCIe ASPM настройки
- ✅ Звуковая карта энергосбережение
- ✅ USB autosuspend по TLP-рецепту
- ✅ NMI Watchdog отключение на батарее
- ✅ VM dirty page оптимизация
- ✅ Режимы сна (deep на батарее, s2idle на сети)

## 💻 Требования

- **ОС:** Fedora 40+ (протестировано на Fedora 43)
- **Ноутбук:** с Intel CPU и дискретной графикой Radeon
- **Зависимости:**
  - `power-profiles-daemon`
  - `iw` (для Wi-Fi управления)
  - `systemd`

## 📁 Структура проекта

```
power-tweaks-hybrid-gpu/
├── install.sh                      # Скрипт установки
├── uninstall.sh                    # Скрипт удаления
├── switch-ppd-profile.sh           # Основной скрипт тюнинга
├── power-profile-monitor.sh        # DBus монитор для PPD
├── power-tweaks.service            # Systemd oneshot сервис
├── power-tweaks.path               # Path монитор для AC статуса
├── power-tweaks.timer              # Периодическая проверка
├── power-profile-monitor.service   # DBus монитор сервис
├── 99-power-tweaks.rules           # Udev правило
├── README.md                       # Этот файл
├── CHANGELOG.md                    # История изменений
└── LICENSE                         # Лицензия MIT
```

## 🔧 Архитектура системы

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Udev rule     │────▶│  power-tweaks   │◀────│  Path monitor   │
│  (plug/unplug)  │     │    service      │     │ (AC изменения)  │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Timer (2 мин)  │────▶│  switch-ppd-    │◀────│  DBus monitor   │
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
```

### Как это работает

1. **Udev rule** обнаруживает подключение/отключение сетевого адаптера AC
2. **Power tweaks service** срабатывает и запускает основной скрипт
3. **Path monitor** отслеживает изменения файла AC online
4. **Timer** периодически проверяет настройки каждые 2 минуты
5. **DBus monitor** реагирует на смену профиля power-profiles-daemon
6. **switch-ppd-profile.sh** применяет все необходимые оптимизации

## 📊 Логика переключения режимов

| Режим | AC статус | PPD профиль | CPU governor | SATA ALPM | Режим сна |
|-------|-----------|-------------|--------------|-----------|-----------|
| Батарея | offline | power-saver | powersave | med_power_with_dipm | deep |
| Сеть | online | balanced | performance | max_performance | s2idle |

## 🚀 Установка

### Автоматизированная установка

```bash
git clone https://github.com/lmdeuser/power-tweaks-Intel-Radeon.git
cd power-tweaks-Intel-Radeon
sudo ./install.sh
```

### Ручная установка

```bash
# Копирование скриптов
sudo cp switch-ppd-profile.sh /usr/local/sbin/
sudo cp power-profile-monitor.sh /usr/local/sbin/
sudo chmod +x /usr/local/sbin/switch-ppd-profile.sh
sudo chmod +x /usr/local/sbin/power-profile-monitor.sh

# Копирование systemd юнитов
sudo cp power-tweaks.service /etc/systemd/system/
sudo cp power-tweaks.path /etc/systemd/system/
sudo cp power-tweaks.timer /etc/systemd/system/
sudo cp power-profile-monitor.service /etc/systemd/system/

# Копирование udev правил
sudo cp 99-power-tweaks.rules /etc/udev/rules.d/

# Включение и запуск
sudo systemctl daemon-reload
sudo systemctl enable power-tweaks.{service,path,timer}
sudo systemctl enable power-profile-monitor.service
sudo systemctl start power-tweaks.{service,path,timer}
sudo systemctl start power-profile-monitor.service
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## ✅ Проверка работы

### Статус всех сервисов

```bash
systemctl status power-tweaks.{service,path,timer}
systemctl status power-profile-monitor.service
```

### Просмотр логов в реальном времени

```bash
sudo journalctl -u power-tweaks.service -f
```

### Проверка текущего режима

```bash
# Статус питания (1 = сеть, 0 = батарея)
cat /sys/class/power_supply/AC/online

# Текущий профиль PPD
powerprofilesctl get
```

### Мониторинг udev событий

```bash
sudo udevadm monitor --property --subsystem-match=power_supply
```

### Проверка применённых настроек

```bash
# CPU governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# SATA ALPM
cat /sys/class/scsi_host/host0/link_power_management_policy

# Режим сна
cat /sys/power/mem_sleep

# Все логи с тегом power-tweaks
journalctl -t power-tweaks

# Логи в реальном времени
sudo journalctl -t power-tweaks -f

# Только ошибки
journalctl -t power-tweaks -p err
```

## 🛠️ Настройка под своё железо

### Нахождение PCI адреса dGPU

```bash
# Найдите вашу видеокарту Radeon
lspci | grep -E "VGA|3D|Radeon"
```

Выход может быть похож на:
```
03:00.0 Display controller: Advanced Micro Devices, Inc. [AMD/ATI] Radeon RX 6500 XT
```

### Редактирование конфигурации

Откройте `switch-ppd-profile.sh` и обновите переменную `DGPU_PCI`:

```bash
# Измените на ваш адрес
readonly DGPU_PCI="0000:03:00.0"
```

### Другие параметры для настройки

```bash
# CPU governor paths (если у вас несколько ядер)
CPU_GOV_PATH="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

# SATA контроллер (если несколько)
SATA_ALPM_PATH="/sys/class/scsi_host/host0/link_power_management_policy"

# Wi-Fi интерфейс
WLAN_DEV="wlan0"  # Может быть wlan1, wlp3s0 и т.д.
```

## 🗑️ Удаление

### Автоматизированное удаление

```bash
sudo ./uninstall.sh
```

### Ручное удаление

```bash
# Отключение и остановка сервисов
sudo systemctl disable --now power-tweaks.{service,path,timer}
sudo systemctl disable --now power-profile-monitor.service

# Удаление файлов
sudo rm /etc/systemd/system/power-tweaks.*
sudo rm /etc/systemd/system/power-profile-monitor.service
sudo rm /usr/local/sbin/switch-ppd-profile.sh
sudo rm /usr/local/sbin/power-profile-monitor.sh
sudo rm /etc/udev/rules.d/99-power-tweaks.rules

# Перезагрузка systemd и udev
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## 🔍 Диагностика

### Проблемы и решения

| Проблема | Решение |
|----------|---------|
| Скрипт не запускается при смене питания | `sudo udevadm control --reload-rules && sudo udevadm trigger` |
| PPD не переключается автоматически | `sudo systemctl status power-profiles-daemon` |
| Логи не появляются | `sudo journalctl -u power-tweaks.service -f` |
| dGPU не отключается на батарее | Проверить PCI адрес: `lspci \| grep Radeon` и обновить скрипт |
| Wi-Fi не переходит в power save | Проверить интерфейс: `iw dev` и обновить `WLAN_DEV` |

### Сбор диагностической информации

```bash
# Полная информация о системе
echo "=== Ноутбук ===" && hostnamectl
echo "=== ОС ===" && cat /etc/os-release | grep PRETTY_NAME
echo "=== CPU ===" && lscpu | grep "Model name"
echo "=== GPU ===" && lspci | grep -E "VGA|3D|Radeon"
echo "=== Батарея ===" && cat /sys/class/power_supply/BAT*/energy_full_design
echo "=== AC ===" && cat /sys/class/power_supply/AC/online
echo "=== PPD ===" && powerprofilesctl get
echo "=== CPU Governor ===" && cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo "=== Логи ===" && journalctl -t power-tweaks -n 20
```

## 📝 Отключение отдельных функций

Если какая-то функция вызывает проблемы, вы можете отключить её, отредактировав `switch-ppd-profile.sh` и закомментировав соответствующую строку в функции `main()`:

```bash
main() {
    local ac_status
    ac_status=$(detect_ac_status)

    if [[ "$ac_status" == "1" ]]; then
        # AC режим
        set_ppd_profile ac
        set_cpu_governor performance
        set_sata_alpm max_performance
        # set_power_down_dgpu  # Закомментируйте, если не нужно
        set_vm_dirty 20 10
        set_sleep_mode s2idle
        # set_wifi_powersave off  # Закомментируйте, если есть проблемы
    else
        # Battery режим
        set_ppd_profile battery
        set_cpu_governor powersave
        set_sata_alpm med_power_with_dipm
        # set_power_down_dgpu  # Закомментируйте, если не нужно
        set_vm_dirty 5 3
        set_sleep_mode deep
        # set_wifi_powersave on  # Закомментируйте, если есть проблемы
    fi
}
```

## 🔐 Права доступа и Sudo

Скрипт требует права `sudo` для доступа к системным параметрам. Вы можете добавить исключение в `sudoers` для автоматического запуска без пароля:

```bash
sudo visudo
```

Добавьте в конец файла:

```
%wheel ALL=(ALL) NOPASSWD: /usr/local/sbin/switch-ppd-profile.sh
%wheel ALL=(ALL) NOPASSWD: /usr/local/sbin/power-profile-monitor.sh
```

## 📚 Дополнительные ресурсы

- [Power Profiles Daemon](https://gitlab.freedesktop.org/upower/power-profiles-daemon)
- [Linux power management](https://www.kernel.org/doc/html/latest/admin-guide/pm/index.html)
- [TLP configuration](https://linrunner.de/tlp/)
- [Fedora Power Management](https://docs.fedoraproject.org/en-US/fedora/latest/system-administrators-guide/power-management/)

## 📄 Лицензия

MIT License - см. файл [LICENSE](LICENSE)

---

**Последнее обновление:** 2026-03-16
