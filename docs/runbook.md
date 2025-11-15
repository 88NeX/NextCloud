# Runbook - основные операции

## Проверка стека
docker stack ls
docker stack ps nextcloud
docker service ls

## Проверка Patroni
patronictl -c /etc/patroni.yml list

## Проверка Redis
redis-cli -a $REDIS_PASSWORD INFO replication

## Откатный план
- восстановить snapshot VM
- выполнить restore Postgres из pgBackRest/WAL-G
- переключить HAProxy на старую подсеть

