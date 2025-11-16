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
flowchart TB
    classDef vip fill:#0d6efd,stroke:#000,color:#fff;
    classDef master fill:#11650c,stroke:#000,color:#fff;
    classDef backup fill:#650c14,stroke:#000,color:#fff;

    Client["Client"] --> VIP:::vip

    subgraph Edge["Edge (2)"]
        direction LR
        K1["srv1\nKeepalived"]:::master --> H1["HAProxy"]
        K2["srv2\nKeepalived"]:::backup --> H2["HAProxy"]
    end

    VIP --> K1
    VIP --> K2

    subgraph Workers["Workers (3)"]
        direction LR
        W12["srv12"]
        W13["srv13"]
        W14["srv14"]
    end

    H1 --> W12
    H1 --> W13
    H1 --> W14
    H2 --> W12
    H2 --> W13
    H2 --> W14

    subgraph PostgreSQL["PostgreSQL + etcd (3)"]
        direction LR
        PG6["srv6\nPG M*"]
        PG7["srv7\nPG S"]
        PG8["srv8\nPG S"]
        E6["etcd"]
        E7["etcd"]
        E8["etcd"]

        PG6 --> E6
        PG7 --> E7
        PG8 --> E8
    end

    W12 --> PG6
    W13 --> PG7
    W14 --> PG8

    subgraph Redis["Redis Cluster (3)"]
        direction LR
        R9["srv9\nR M1"]
        R10["srv10\nR M2"]
        R11["srv11\nR M3"]
        R10r["R S2"]
        R11r["R S3"]
        R9r["R S1"]

        R9 --> R10r
        R10 --> R11r
        R11 --> R9r
    end

    W12 --> R9
    W13 --> R10
    W14 --> R11

    subgraph External["External"]
        S3["S3"]
    end

    W12 --> S3
    W13 --> S3
    W14 --> S3

    subgraph ControlPlane["Swarm Managers (3)"]
        direction LR
        M3["srv3\nMGR"]
        M4["srv4\nMGR"]
        M5["srv5\nMGR"]
        M3 --> M4 --> M5
    end

    M3 -.-> W12
    M4 -.-> W13
    M5 -.-> W14

    subgraph Utility["Utility (1)"]
        U15["srv15\nCron+Mon"]
    end

    U15 --> PG6
    U15 --> R9
    U15 --> H1
    U15 --> W12
    U15 --> S3
```
