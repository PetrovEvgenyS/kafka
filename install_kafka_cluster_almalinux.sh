#!/bin/bash
# Скрипт для установки и настройки Apache Kafka 3.9.0 с использованием KRaft
# Скрипт настройки Kafka для каждой ноды (Node 1, Node 2, Node 3)
# Выполняется на каждой ноде индивидуально с соответствующими параметрами node.id и hostname

# Общие параметры
KAFKA_VERSION="3.9.0"       # Версия Kafka
KAFKA_DOWNLOAD_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
KAFKA_USER="kafka"          # Пользователь
KAFKA_GROUP="kafka"         # Группа
INSTALL_DIR="/opt/kafka"    # Куда будет установлен Kafka
DATA_DIR="/var/lib/kafka/data"   # Где будут хранится данные Kafka (сообщения)
LOG_DIR="/var/log/kafka"    # Где будут хранится логи Kafka

# Параметры кластера
# Уникальные параметры для каждой ноды (Настройте отдельно для Node 1, Node 2, Node 3)
NODE_ID="$1"    # При запуске передать node.id: 1, 2 или 3
HOSTNAME="$2"   # При запуске передать hostname или IP адрес ноды
CONTROLLER_QUORUM="1@10.100.10.1:9093,2@10.100.10.2:9093,3@10.100.10.3:9093"    # Список кворума контроллеров
CONTROLLER_QUORUM_BOOTSTRAP="10.100.10.1:9093,10.100.10.2:9093"                 # Список кворума контроллеров для брокера
ROLES="broker,controller"   # Роли узла

### ЦВЕТА ##
ESC=$(printf '\033') RESET="${ESC}[0m" MAGENTA="${ESC}[35m" RED="${ESC}[31m" GREEN="${ESC}[32m"

### Функции цветного вывода ##
magentaprint() { printf "${MAGENTA}%s${RESET}\n" "$1"; }
errorprint() { printf "${RED}%s${RESET}\n" "$1"; }
greenprint() { printf "${GREEN}%s${RESET}\n" "$1"; }


# -------------------------------------------------------------------------------------------------------------------------


# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then
    errorprint "Скрипт должен быть запущен с правами root!"
    exit 1
fi

# Проверка заданных параметров
checking_the_set_parameters() {
    magentaprint "Проверка заданных параметров..."
    if [ -z "$NODE_ID" ] || [ -z "$HOSTNAME" ]; then
        echo "Использование: $0 <NODE_ID> <HOSTNAME>"
        echo "Пример: $0 1 node_1"
        exit 1
    fi
}

# Установка зависимостей
installing_dependencies() {
    magentaprint "Обновление пакетов системы..."
    dnf update -y

    magentaprint "Установка необходимых пакетов..."
    dnf install -y java-11-openjdk wget tar net-tools
}


# Создание пользователя и группы для Kafka
creating_user_group() {
    magentaprint "Создание пользователя и группы для Kafka..."
    groupadd -r $KAFKA_GROUP
    useradd -r -g $KAFKA_GROUP -s /sbin/nologin -d $INSTALL_DIR $KAFKA_USER
}


# Скачивание и распаковка Kafka
downloading_unpacking_kafka() {
    magentaprint "Скачивание Apache Kafka..."
    wget "$KAFKA_DOWNLOAD_URL" -O /tmp/kafka.tgz

    magentaprint "Распаковка Apache Kafka..."
    mkdir -p "$INSTALL_DIR"
    tar -xvzf /tmp/kafka.tgz --strip-components=1 -C "$INSTALL_DIR"
    rm -f /tmp/kafka.tgz
}


# Создание директорий для данных и логов
create_dir_for_data_and_log() {
    magentaprint "Создание директорий для данных и логов..."
    mkdir -p "$DATA_DIR" "$LOG_DIR" 
    chown -R $KAFKA_USER:$KAFKA_GROUP "$DATA_DIR" "$LOG_DIR" "$INSTALL_DIR"
    chmod 0700 "$DATA_DIR" "$LOG_DIR" "$INSTALL_DIR"
}


# Генерация cluster.id (выполнить на первой ноде и скопировать на другие)
generation_cluster_id() {
    magentaprint "Генерация cluster.id..."
    # Проверка наличия cluster.id
    if [ ! -f /tmp/cluster.id ]; then
        magentaprint "Cluster ID не найден, создание нового..."
        # Если это Node 1, то генерируем новый Cluster ID
        if [ "$NODE_ID" -eq 1 ]; then
            # CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid) - 2 вариант генерации
            CLUSTER_ID=$(uuidgen)
            magentaprint "Cluster ID сгенерирован: $CLUSTER_ID"
            echo "$CLUSTER_ID" > /tmp/cluster.id
            echo "$CLUSTER_ID" > $INSTALL_DIR/cluster.id
        else
            # Если это не Node 1, то читаем Cluster ID из файла
            errorprint "Ошибка: Cluster ID должен быть предварительно создан на Node 1."
            exit 1
        fi
    else
        # Если файл уже существует, читаем Cluster ID из него
        magentaprint "Cluster ID уже существует, чтение из файла..."
        magentaprint "Cluster ID используется: $CLUSTER_ID"
        CLUSTER_ID=$(cat /tmp/cluster.id)
    fi  
}


# Создание конфигурации Kafka
create_configuration_kafka() {
    magentaprint "Создание конфигурации Kafka..."

cat <<EOF > "$INSTALL_DIR/config/kafka-node${NODE_ID}.properties"
### Роли узла
process.roles=$ROLES

###  Уникальный ID узла
node.id=$NODE_ID

###  Кворум контроллеров
# Удалите переменную, если сервер выполняет только роль брокера.
controller.quorum.voters=$CONTROLLER_QUORUM

### Список серверов, к которым брокеры должны подключаться для установления связи с кворумом контроллера. 
# Раскомментировать, если сервер выполняет только роль брокера.
#controller.quorum.bootstrap.servers=$CONTROLLER_QUORUM_BOOTSTRAP

### Слушатели и адреса. Для брокера
# Раскомментировать, если сервер выполняет только роль брокера.
#listener.security.protocol.map=PLAINTEXT:PLAINTEXT
#listeners=PLAINTEXT://${HOSTNAME}:9092
#advertised.listeners=PLAINTEXT://${HOSTNAME}:9092
#inter.broker.listener.name=PLAINTEXT

###  Слушатели и адреса. Для брокера и контроллера
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://${HOSTNAME}:9092,CONTROLLER://${HOSTNAME}:9093
advertised.listeners=PLAINTEXT://${HOSTNAME}:9092
inter.broker.listener.name=PLAINTEXT

###  Каталог для данных Kafka (сообщения)
log.dirs=${DATA_DIR}/data

###  Производительность и обработка
num.network.threads=3
num.io.threads=8
# 168 часов (7 дней)
log.retention.hours=168
# 1073741824 байт (1 ГБ)
log.segment.bytes=1073741824
# 300000 мс (5 мин)
log.retention.check.interval.ms=300000

###  Параметры репликации
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
EOF
}


# Форматирование хранилища Kafka
formatting_storage_kafka() {
    magentaprint "Форматирование хранилища Kafka..."
    sudo -u kafka "$INSTALL_DIR/bin/kafka-storage.sh" format \
        --config "$INSTALL_DIR/config/kafka-node${NODE_ID}.properties" \
        --cluster-id "$CLUSTER_ID"
}


# Создание systemd-сервиса Kafka
create_unit_kafka() {
    magentaprint "Создание systemd-сервиса Kafka для Node ${NODE_ID}..."
    echo " "

cat <<EOF > /etc/systemd/system/kafka.service
[Unit]
Description=Apache Kafka $KAFKA_VERSION Service
After=network.target

[Service]
Type=simple
User=$KAFKA_USER
Group=$KAFKA_GROUP
ExecStart=${INSTALL_DIR}/bin/kafka-server-start.sh ${INSTALL_DIR}/config/kafka-node${NODE_ID}.properties
ExecStop=${INSTALL_DIR}/bin/kafka-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
Alias=kafka.service
EOF
}


# Перезагрузка systemd и запуск Kafka как сервиса
start_enable_kafka() {
    magentaprint "Перезагрузка systemd и запуск Kafka как сервиса..."
    systemctl daemon-reload
    systemctl enable kafka
    systemctl start kafka
}


# Функция проверки состояния ZooKeeper:
check_status_kafka() {
    magentaprint "Проверка статуса службы Kafka..."
    systemctl status kafka --no-pager
    magentaprint "Kafka настроена и запущена на узле ${HOSTNAME} с node.id=${NODE_ID}."
}


# Копирование Cluster ID на другие ноды
copy_cluster_id() {
    if [ "$NODE_ID" -eq 1 ]; then
        echo; magentaprint "Необходимо скопировать Cluster ID на другие ноды, запустите команду:"
        echo "for i in {2..3}; do scp /tmp/cluster.id vagrant@10.100.10.\$i:/tmp/cluster.id; done"
    fi
}

# Создание функций main.
main() {
    checking_the_set_parameters
    installing_dependencies
    creating_user_group
    downloading_unpacking_kafka
    create_dir_for_data_and_log
    generation_cluster_id
    create_configuration_kafka
    formatting_storage_kafka
    create_unit_kafka
    start_enable_kafka
    check_status_kafka
    copy_cluster_id
}

# Вызов функции main.
main