## **Этап 1.1: Установка и настройка серверов**

### **Подготовка к установке**

#### **1. Подготовка оборудования**
```
1. Проверка совместимости оборудования с Proxmox VE
2. Подготовка USB-накопителя с ISO Proxmox VE
3. Настройка BIOS/UEFI:
   - Включение_virtualization (Intel VT-x/AMD-V)
   - Включение IOMMU (Intel VT-d/AMD Vi)
   - Отключение Secure Boot
   - Настройка boot order
```

#### **2. Сетевые требования**
```
- Доступ к интернету для загрузки
- Статические IP адреса для серверов
- Доступ к локальному репозиторию (опционально)
```

### **Установка Proxmox VE**

#### **3. Загрузка и установка**
```
1. Загрузиться с USB с Proxmox VE ISO
2. Выбрать "Install Proxmox VE"
3. Принять лицензионное соглашение
4. Выбрать диск для установки (рекомендуется RAID 1)
5. Настроить локаль:
   - Country: Russia
   - Language: English
   - Timezone: Europe/Moscow
6. Настроить сеть:
   - Management interface: выберите основной интерфейс
   - Hostname: server1.domain.local (или server2.domain.local)
   - IP Address: статический IP
   - Netmask: 255.255.255.0 (или соответствующая маска)
   - Gateway: IP шлюза
   - DNS Server: IP DNS серверов
7. Установить root пароль
8. Подтвердить установку
9. Перезагрузка после установки
```

#### **4. Первичная настройка после установки**
```
1. Вход в веб-интерфейс:
   - URL: https://[SERVER_IP]:8006
   - Username: root
   - Password: установленный пароль

2. Проверка статуса системы:
   - System → Syslog
   - System → Updates
   - System → Network

3. Обновление системы:
   # apt update && apt dist-upgrade -y
```

### **Настройка сети**

#### **5. Настройка bonding (если несколько сетевых интерфейсов)**
```bash
# Резервирование сетевых интерфейсов
# Файл: /etc/network/interfaces

auto lo
iface lo inet loopback

iface enp0s3 inet manual

iface enp0s4 inet manual

auto bond0
iface bond0 inet static
    address 192.168.1.10/24
    gateway 192.168.1.1
    bond-slaves enp0s3 enp0s4
    bond-mode active-backup
    bond-miimon 100
    bond-downdelay 200
    bond-updelay 200
```

#### **6. Настройка VLAN (если требуется)**
```bash
# Добавление VLAN интерфейсов
auto bond0.10
iface bond0.10 inet static
    address 10.10.10.10/24

auto bond0.20
iface bond0.20 inet static
    address 10.10.20.10/24
```

### **Настройка времени**

#### **7. Настройка NTP**
```bash
# Проверка текущего времени
timedatectl

# Настройка timezone
timedatectl set-timezone Europe/Moscow

# Настройка NTP серверов
# Файл: /etc/systemd/timesyncd.conf
[Time]
NTP=ntp.pool.org 0.pool.ntp.org 1.pool.ntp.org
FallbackNTP=2.pool.ntp.org 3.pool.ntp.org

# Перезапуск службы
systemctl restart systemd-timesyncd
systemctl enable systemd-timesyncd

# Проверка синхронизации
timedatectl status
```

### **Настройка SSH доступа**

#### **8. Настройка SSH ключей**
```bash
# На локальной машине создать SSH ключи
ssh-keygen -t rsa -b 4096 -C "admin@domain.local"

# Скопировать публичный ключ на сервер
ssh-copy-id root@server_ip

# На сервере настроить SSH
# Файл: /etc/ssh/sshd_config
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no

# Перезапуск SSH
systemctl restart ssh
```

#### **9. Настройка firewall для SSH**
```bash
# Временное разрешение SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Сохранение правил (будет настроено позже)
```

### **Настройка хранилища**

#### **10. Настройка LVM (если не настроено автоматически)**
```bash
# Проверка существующих volumes
lvdisplay
vgdisplay
pvdisplay

# Создание logical volumes если нужно
lvcreate -L 100G -n vm-storage pve
lvcreate -L 50G -n container-storage pve
```

#### **11. Настройка дополнительных дисков**
```bash
# Проверка дисков
lsblk
fdisk -l

# Создание разделов
fdisk /dev/sdb

# Создание filesystem
mkfs.ext4 /dev/sdb1

# Монтирование
mkdir /mnt/data
mount /dev/sdb1 /mnt/data

# Автоматическое монтирование
echo "/dev/sdb1 /mnt/data ext4 defaults 0 2" >> /etc/fstab
```

### **Базовая настройка безопасности**

#### **12. Настройка firewall (базовая)**
```bash
# Установка iptables-persistent
apt install iptables-persistent

# Базовые правила
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешить loopback
iptables -A INPUT -i lo -j ACCEPT

# Разрешить established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешить SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Разрешить Proxmox web interface
iptables -A INPUT -p tcp --dport 8006 -j ACCEPT

# Разрешить Proxmox VE services
iptables -A INPUT -p tcp --dport 5900:6000 -j ACCEPT  # VNC
iptables -A INPUT -p tcp --dport 80 -j ACCEPT        # HTTP
iptables -A INPUT -p tcp --dport 443 -j ACCEPT       # HTTPS

# Сохранить правила
iptables-save > /etc/iptables/rules.v4
```

#### **13. Настройка fail2ban**
```bash
# Установка fail2ban
apt install fail2ban

# Настройка конфигурации
# Файл: /etc/fail2ban/jail.local
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[proxmox]
enabled = true
port = 8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 3600

# Запуск службы
systemctl enable fail2ban
systemctl start fail2ban
```

### **Настройка мониторинга хоста**

#### **14. Установка базовых инструментов мониторинга**
```bash
# Установка системных утилит
apt install htop iotop iftop nmon sysstat

# Настройка логирования
# Файл: /etc/logrotate.d/proxmox
/var/log/pve/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 root adm
}
```

#### **15. Настройка SNMP (для внешнего мониторинга)**
```bash
# Установка SNMP
apt install snmpd snmp

# Настройка SNMP
# Файл: /etc/snmp/snmpd.conf
rocommunity public localhost
syslocation ServerRoom
syscontact admin@domain.local

# Запуск службы
systemctl enable snmpd
systemctl start snmpd
```

### **Финальная проверка**

#### **16. Проверка всех сервисов**
```bash
# Проверка статуса системных служб
systemctl status pve-cluster
systemctl status pvedaemon
systemctl status pveproxy
systemctl status corosync

# Проверка дискового пространства
df -h

# Проверка памяти
free -h

# Проверка CPU
top -bn1 | grep "Cpu(s)"

# Проверка сети
ip addr show
ping -c 4 8.8.8.8
```

#### **17. Создание резервной копии конфигурации**
```bash
# Резервное копирование конфигурации
tar -czf /root/proxmox-config-backup-$(date +%Y%m%d).tar.gz /etc/pve/

# Копирование на внешний носитель
scp /root/proxmox-config-backup-*.tar.gz user@backup-server:/backup/
```

### **Документация результатов**

#### **18. Документирование конфигурации**
```
Создать документ с информацией:
- IP адреса серверов
- MAC адреса сетевых интерфейсов
- Конфигурация сети
- Пароли и учетные записи (в зашифрованном виде)
- Контактная информация администраторов
- Процедуры восстановления
```

**Время выполнения:** 2-4 часа на сервер
**Следующий этап:** 1.2 Настройка кластера Proxmox

Готовы перейти к следующему этапу или хотите уточнить что-то по текущему этапу?
