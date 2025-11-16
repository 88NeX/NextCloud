# ansible-nextcloud-ha

Автоматизация развёртывания HA Nextcloud (Docker Swarm) с PostgreSQL (Patroni), Redis Sentinel, HAProxy+Keepalived, S3 backend.

Версии:
- Nextcloud 32.0.1
- PostgreSQL 17.6
- Redis 7
- Ubuntu 22.04 LTS (рекомендуется)

Перед использованием:
- заменить `changeme_*` в `.env` и group_vars на реальные секреты
- переместить секреты в Docker Secrets / Vault
- проверить inventory/hosts.yml и ansible connectivity

## 📁 Структура проекта
```
.
├── ansible.cfg
├── config
│   ├── nginx.conf
│   ├── redis.conf
│   └── sentinel.conf
├── docs
│   └── runbook.md
├── group_vars
│   ├── all.yml
│   ├── lb.yml
│   ├── managers.yml
│   ├── postgres.yml
│   ├── redis.yml
│   └── workers.yml
├── haproxy.cfg
├── haproxy.cfg.gefault
├── inventory
│   └── hosts.yml
├── keepalived.conf
├── keepalived.conf.gefault
├── playbooks
│   ├── 00_prepare.yml
│   ├── 01_swarm.yml
│   ├── 02_lb.yml
│   ├── 03_postgres.yml
│   ├── 04_redis.yml
│   └── 05_deploy_nextcloud.yml
├── README.md
├── roles
│   ├── common
│   │   └── tasks
│   │       └── main.yml
│   ├── docker
│   │   └── tasks
│   │       └── main.yml
│   ├── haproxy
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       ├── haproxy.cfg.j2
│   │       └── keepalived.conf.j2
│   ├── monitoring
│   │   └── tasks
│   │       └── main.yml
│   ├── nextcloud_stack
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       ├── docker-stack.yml.j2
│   │       └── env.j2
│   ├── postgresql_ha
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       └── patroni.yml.j2
│   ├── redis_cluster
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       ├── redis.conf.j2
│   │       └── sentinel.conf.j2
│   └── swarm
│       └── tasks
│           ├── init.yml
│           ├── join_manager.yml
│           └── join_worker.yml
└── templates
    ├── nextcloud-config.php.j2
    └── patroni-bootstrap.sh
```

Полезные команды для запуска

# подготовить окружение
export $(cat .env | xargs)

# запустить playbooks
```
ansible-playbook playbooks/00_prepare.yml
ansible-playbook playbooks/01_swarm.yml
ansible-playbook playbooks/02_lb.yml
ansible-playbook playbooks/03_postgres.yml
ansible-playbook playbooks/04_redis.yml
ansible-playbook playbooks/05_deploy_nextcloud.yml
```

```mermaid
flowchart TD
    subgraph External
        S3["External S3 Bucket\n(cloud.ru)"]
    end

    Client["Client\n(User/Browser)"] -->|HTTPS| VIP["Virtual IP\n192.168.10.100\n(Keepalived VRRP)"]

    subgraph Edge_and_Workers["Nextcloud Workers + Edge (srv4–srv6)"]
        direction TB

        subgraph srv4["srv4 (Worker #1)"]
            K4["Keepalived\n(MASTER)"] 
            H4["HAProxy"]
            N4["nginx"]
            F4["nextcloud-fpm"]
        end

        subgraph srv5["srv5 (Worker #2)"]
            K5["Keepalived\n(BACKUP)"]
            H5["HAProxy"]
            N5["nginx"]
            F5["nextcloud-fpm"]
        end

        subgraph srv6["srv6 (Worker #3)"]
            K6["Keepalived\n(BACKUP)"]
            H6["HAProxy"]
            N6["nginx"]
            F6["nextcloud-fpm"]
        end

        %% VRRP между Keepalived
        K4 <-->|VRRP multicast| K5
        K5 <-->|VRRP multicast| K6

        %% HAProxy балансирует между всеми
        H4 <-->|HTTP/HTTPS| H5
        H5 <-->|HTTP/HTTPS| H6

        %% Внутри каждой ноды
        H4 --> N4 --> F4
        H5 --> N5 --> F5
        H6 --> N6 --> F6
    end

    VIP --> K4

    subgraph Stateful["Stateful Nodes (srv1–srv3)"]
        direction TB

        subgraph srv1["srv1"]
            E1["etcd1"]
            P1["PostgreSQL\n(MASTER*)"]
            R1a["Redis M1"]
            R1b["Redis S2"]
        end

        subgraph srv2["srv2"]
            E2["etcd2"]
            P2["PostgreSQL\n(REPLICA)"]
            R2a["Redis M2"]
            R2b["Redis S3"]
        end

        subgraph srv3["srv3"]
            E3["etcd3"]
            P3["PostgreSQL\n(REPLICA)"]
            R3a["Redis M3"]
            R3b["Redis S1"]
        end
    end

    subgraph Cron["Background"]
        C1["Cron\n(in Swarm)"]
    end

    %% Nextcloud → Stateful
    F4 -->|SQL| P1
    F4 -->|Redis| R1a
    F4 -->|S3 API| S3

    F5 -->|SQL| P2
    F5 -->|Redis| R2a
    F5 -->|S3 API| S3

    F6 -->|SQL| P3
    F6 -->|Redis| R3a
    F6 -->|S3 API| S3

    %% Cron
    C1 -->|SQL, S3, Redis| Stateful
    C1 -.->|Runs on one worker| Edge_and_Workers

    %% Примечание
    classDef master fill:#11650c,stroke:#000;
    classDef backup fill:#650c14,stroke:#000;
    class K4 master
    class K5,K6 backup
```
