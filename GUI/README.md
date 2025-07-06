# Kafka UI — запуск через Docker Compose

Этот проект предназначен для быстрого запуска веб-интерфейса управления Apache Kafka с помощью [Kafka UI](https://github.com/provectus/kafka-ui).

## Быстрый старт
1. Перейдите в папку GUI:
   ```sh
   cd GUI
   ```
2. Запустите сервис:
   ```sh
   docker-compose up -d
   ```
3. Откройте браузер и перейдите по адресу: [http://localhost:8080](http://localhost:8080)

## Конфигурация
В файле `docker-compose.yaml` указаны параметры подключения к вашему кластеру Kafka:
- `KAFKA_CLUSTERS_0_NAME` — имя кластера (kraft-cluster)
- `KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS` — список bootstrap-серверов Kafka (10.100.10.1:9092, 10.100.10.2:9092, 10.100.10.3:9092)

## Остановка
Для остановки и удаления контейнера выполните:
```sh
docker-compose down
```
