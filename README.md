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

Полезные команды для запуска

# подготовить окружение
export $(cat .env | xargs)

# запустить playbooks
ansible-playbook playbooks/00_prepare.yml
ansible-playbook playbooks/01_swarm.yml
ansible-playbook playbooks/02_lb.yml
ansible-playbook playbooks/03_postgres.yml
ansible-playbook playbooks/04_redis.yml
ansible-playbook playbooks/05_deploy_nextcloud.yml
