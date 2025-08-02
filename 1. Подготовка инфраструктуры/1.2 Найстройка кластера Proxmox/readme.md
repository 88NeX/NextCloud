## **Этап 1.2: Настройка кластера Proxmox**

### **Подготовка к созданию кластера**

#### **1. Проверка предварительных требований**
```bash
# Проверка версий Proxmox на обоих серверах
pveversion

# Проверка сетевой связности между серверами
ping -c 4 [IP_другого_сервера]

# Проверка разрешения имен (если настроен DNS)
nslookup server1.domain.local
nslookup server2.domain.local

# Проверка времени на обоих серверах
timedatectl status
```

#### **2. Настройка /etc/hosts**
```bash
# На обоих серверах отредактировать файл:
# Файл: /etc/hosts

127.0.0.1 localhost.localdomain localhost
192.168.1.10 server1.domain.local server1 pvelocalhost
192.168.1.11 server2.domain.local server2

# Проверка разрешения имен
ping server1
ping server2
```

### **Создание кластера Proxmox**

#### **3. Создание кластера на первом сервере**
```bash
# На сервере server1 выполнить:
pvecm create nextcloud-cluster -- ring0_addr 192.168.1.10

# Проверка статуса кластера
pvecm status

# Просмотр конфигурации кластера
cat /etc/pve/corosync.conf
```

#### **4. Добавление второго сервера в кластер**
```bash
# На сервере server1 получить токен для присоединения:
pvecm add-node server2.domain.local

# Или вручную на server2 выполнить:
pvecm add nextcloud-cluster 192.168.1.10

# Ввод токена при запросе (если создавался через add-node)
```

#### **5. Проверка кластера**
```bash
# На обоих серверах проверить статус:
pvecm status

# Должен показать 2 узла в кластере

# Проверка конфигурации:
pvecm nodes

# Проверка кольца кластера:
corosync-cfgtool -s
```

### **Настройка кластерной сети**

#### **6. Настройка Corosync для двух интерфейсов (опционально)**
```bash
# Если есть отдельная сеть для кластера
# Редактировать: /etc/pve/corosync.conf

logging {
  debug: off
  to_logfile: yes
  logfile: /var/log/corosync/corosync.log
  to_syslog: yes
}

nodelist {
  node {
    ring0_addr: 192.168.1.10
    ring1_addr: 10.10.10.10  # отдельный интерфейс для кластера
    nodeid: 1
  }
  node {
    ring0_addr: 192.168.1.11
    ring1_addr: 10.10.10.11
    nodeid: 2
  }
}
```

#### **7. Настройка QDevice для кворума (для 2-узлового кластера)**
```bash
# Установка QDevice на отдельном сервере или одном из узлов
apt install corosync-qdevice

# Настройка QDevice
# Файл: /etc/corosync/qnetd.conf

# Инициализация QDevice
systemctl enable corosync-qdevice
systemctl start corosync-qdevice

# Добавление QDevice в кластер
pvecm qdevice setup [IP_QDEVICE]
```

### **Настройка shared storage**

#### **8. Настройка shared storage для кластера**
```bash
# Вариант 1: NFS storage (если есть NFS сервер)
# На обоих серверах:
mkdir /mnt/shared-storage

# В веб-интерфейсе Proxmox:
# Datacenter → Storage → Add → NFS
# ID: shared-nfs
# Server: [IP_NFS_SERVER]
# Export: /shared/proxmox
# Content: images,iso,backup

# Вариант 2: DRBD (для двухсерверной конфигурации)
# Установка DRBD
apt install drbd-dkms drbd-utils

# Настройка DRBD
# Файл: /etc/drbd.d/shared.res
resource shared {
  on server1 {
    device    /dev/drbd0;
    disk      /dev/sdc1;
    address   192.168.1.10:7789;
    meta-disk internal;
  }
  on server2 {
    device    /dev/drbd0;
    disk      /dev/sdc1;
    address   192.168.1.11:7789;
    meta-disk internal;
  }
}

# Инициализация DRBD
drbdadm create-md shared
drbdadm up shared
drbdadm -- --overwrite-data-of-peer primary shared/0

# Создание filesystem
mkfs.ext4 /dev/drbd0

# Монтирование
mkdir /mnt/shared-storage
mount /dev/drbd0 /mnt/shared-storage
```

#### **9. Настройка LVM в кластере**
```bash
# Если используется shared storage с LVM
# Установка cluster-aware LVM
apt install lvm2-cluster

# Настройка LVM для кластера
# Файл: /etc/lvm/lvm.conf
# Установить locking_type = 3 для cluster locking

# Создание volume group
vgcreate shared-vg /dev/drbd0

# Создание logical volumes
lvcreate -L 100G -n vm-storage shared-vg
lvcreate -L 50G -n container-storage shared-vg
```

### **Настройка HA manager**

#### **10. Включение и настройка HA**
```bash
# Проверка статуса HA manager
systemctl status pve-ha-lrm

# Включение HA для ресурсов
# В веб-интерфейсе:
# Datacenter → HA → Resources

# Настройка fencing (опционально, но рекомендуется)
# Установка fence agents
apt install fence-agents

# Настройка fencing в кластере
pvecm fence add server1 --mode power --ip [IP_ILO] --username admin --password [PASSWORD]
pvecm fence add server2 --mode power --ip [IP_ILO] --username admin --password [PASSWORD]
```

#### **11. Настройка watchdog**
```bash
# Проверка наличия watchdog
ls -la /dev/watchdog*

# Установка watchdog
apt install watchdog

# Настройка watchdog
# Файл: /etc/watchdog.conf
watchdog-device = /dev/watchdog
realtime = yes
priority = 1

# Включение watchdog
systemctl enable watchdog
systemctl start watchdog
```

### **Тестирование кластера**

#### **12. Тестирование failover**
```bash
# Создание тестовой VM или container
# В веб-интерфейсе создать тестовый контейнер

# Включение HA для тестового ресурса
# Datacenter → HA → Resources → Add

# Тестирование failover:
# 1. Отключить один сервер (выключить питание)
# 2. Проверить, что ресурсы переехали на другой сервер
# 3. Включить первый сервер
# 4. Проверить, что кластер восстановился

# Мониторинг процесса:
watch pvecm status
```

#### **13. Тестирование shared storage**
```bash
# Создание файла на одном сервере
echo "Test file from server1" > /mnt/shared-storage/test.txt

# Проверка доступности на другом сервере
cat /mnt/shared-storage/test.txt

# Тестирование одновременной записи
# (требует careful locking mechanisms)
```

### **Мониторинг и настройка алертов**

#### **14. Настройка мониторинга кластера**
```bash
# Проверка статуса кластера через CLI
pvecm status
pvecm nodes
pvecm quorum

# Настройка email алертов
# В веб-интерфейсе:
# Datacenter → Options → Email

# Настройка SNMP для внешнего мониторинга
# Установка SNMP на оба сервера
apt install snmpd snmp

# Настройка SNMP community
# Файл: /etc/snmp/snmpd.conf
rocommunity public localhost
extend pve-cluster-status /usr/bin/pvecm status
```

#### **15. Создание скриптов мониторинга**
```bash
# Создание скрипта проверки кластера
# Файл: /usr/local/bin/check-cluster.sh
#!/bin/bash
CLUSTER_STATUS=$(pvecm status | grep "Quorate" | awk '{print $2}')
if [ "$CLUSTER_STATUS" != "yes" ]; then
    echo "CRITICAL: Cluster is not quorate"
    exit 2
fi

NODES_COUNT=$(pvecm nodes | grep -c "^[0-9]")
if [ "$NODES_COUNT" -lt 2 ]; then
    echo "WARNING: Only $NODES_COUNT nodes in cluster"
    exit 1
fi

echo "OK: Cluster is healthy with $NODES_COUNT nodes"
exit 0

# Сделать скрипт исполняемым
chmod +x /usr/local/bin/check-cluster.sh
```

### **Документация и финальная проверка**

#### **16. Документирование конфигурации кластера**
```bash
# Сохранение конфигурации кластера
cp /etc/pve/corosync.conf /root/corosync.conf.backup.$(date +%Y%m%d)

# Документация параметров:
# - Cluster name
# - Node names and IPs
# - Ring configuration
# - Quorum settings
# - Storage configuration
# - HA settings
```

#### **17. Финальная проверка**
```bash
# Комплексная проверка кластера
echo "=== Cluster Status ==="
pvecm status

echo "=== Cluster Nodes ==="
pvecm nodes

echo "=== Quorum Information ==="
pvecm quorum

echo "=== Network Configuration ==="
corosync-cfgtool -s

echo "=== Ring Status ==="
corosync-quorumtool -s

# Проверка времени на всех узлах
for node in server1 server2; do
    echo "=== Time on $node ==="
    ssh $node "timedatectl status"
done
```

### **Устранение неполадок**

#### **18. Частые проблемы и решения**
```bash
# Проблема: Узлы не видят друг друга
# Решение: Проверить сетевую связность и /etc/hosts

# Проблема: Кластер не кворумный
# Решение: Проверить количество узлов и настройки QDevice

# Проблема: Shared storage недоступен
# Решение: Проверить монтирование и права доступа

# Проблема: HA не работает
# Решение: Проверить статус pve-ha-lrm и конфигурацию fencing
```

**Время выполнения:** 3-5 часов
**Следующий этап:** 2.1 Настройка Load Balancer

Готовы перейти к следующему этапу или хотите уточнить что-то по текущему этапу?