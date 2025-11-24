#!/bin/bash

# Посилання 
URL_INSTALL_CONF="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/VM-RocketChat-dev/install.conf"
URL_INSTALL="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/VM-RocketChat-dev/install.sh"
URL_MAKE_TEMPLATE="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/VM-RocketChat-dev/make-template.sh"
URL_PARTS="https://github.com/Dr1xam/deployment-tool/releases/download/v1.0/"
URL_DELETE_SCRIPT="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/VM-RocketChat-dev/delete-script.sh"
URL_MAKE_VM_SETTINGS="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/VM-RocketChat-dev/make-vm-settings.sh"
URL_MAKE_ROCKETCHAT="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/VM-RocketChat-dev/make-rocketchat.sh"
URL_ROCKETCHAT="https://github.com/Dr1xam/deployment-tool/releases/download/v1.0/Rocketchat.tar.gz"

# Шлях до фінального файлу бекапу

FINAL_FILE_NAME="vzdump-qemu-101.vma.zst"
FINAL_FILE_DIRECTORY="/var/lib/vz/dump"
FINAL_FILE_PATH="${FINAL_FILE_DIRECTORY}/${FINAL_FILE_NAME}"

# Приблизний розмір архіву для коректної смужки (21 файл по 100мб + 1 шматок ~23мб)
# Це потрібно, щоб pv показував саме відсотки (%). Якщо розмір зміниться, смужка просто дійде до кінця раніше або пізніше.
TOTAL_SIZE="2120m"

# початкова директорія 
START_PATH=$PWD

# --- ПЕРЕВІРКА ТА ВСТАНОВЛЕННЯ PV ---
if ! command -v pv &> /dev/null; then
    echo "Встановлення pv для відображення єдиної смужки завантаження..."
    apt-get update -qq && apt-get install -y pv
fi

#Назви частин архіву з бекапом убунту сервера
PART_PREFIX="part_archive_"
SUFFIXES=(
  aa ab ac ad ae af ag ah ai aj ak al am an ao ap aq ar as at au av
)

cd ${FINAL_FILE_DIRECTORY}

# Формуємо список усіх URL в один рядок
URL_LIST=""
for suffix in "${SUFFIXES[@]}"; do
  URL_LIST="${URL_LIST} ${URL_PARTS}${PART_PREFIX}${suffix}"
done

echo "Початок завантаження шаблону для віртуальних машин "


# Завантаження + Склеювання (однією смужкою)
wget -q -O - $URL_LIST | pv -s $TOTAL_SIZE > "$FINAL_FILE_NAME"

# Перевірка статусу (pipefail гарантує помилку, якщо wget впаде)
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "Помилка завантаження!"
    rm -f "$FINAL_FILE_NAME"
    cd ${START_PATH}
    exit 1
fi

#скрипт який все удалить + конфіг
wget -q --show-progress "$URL_INSTALL_CONF"
wget -q --show-progress "$URL_DELETE_SCRIPT"
#інсталяція інших файлів
wget -q --show-progress "$URL_MAKE_VM_SETTINGS"
wget -q --show-progress "$URL_MAKE_TEMPLATE"
wget -q --show-progress "$URL_MAKE_ROCKETCHAT"
wget -q --show-progress "$URL_ROCKETCHAT"
#інсталтор в останю чергу
wget -q --show-progress "$URL_INSTALL"

#Перевірка чи завантажено скріпти
if [ ! -f delete-script.sh ] || [ ! -f install.conf ] || [ ! -f make-template.sh ] || [ ! -f install.sh ] || [ ! -f make-vm-settings.sh ] || [ ! -f make-rocketchat.sh ] || [ ! -f Rocketchat.tar.gz ]; then
    echo "Помилка: Не всі файли завантажено."
    rm -f ${FINAL_FILE_NAME}
    rm -f install.conf
    rm -f make-template.sh
    rm -f install.sh
    rm -f make-vm-settings.sh
    rm -f vm.conf
    rm -f make_template.log
    rm -f meke-rocketchat.sh
    rm -f delete-script.sh
    rm -f Rocketchat.tar.gz
    cd ${START_PATH}
    rm -f download.sh
    exit 1
fi

chmod +x install.sh
chmod +x make-vm-settings.sh
chmod +x delete-script.sh
chmod +x make-template.sh
chmod +x make-rocketchat.sh
./install.sh

#./delete-script.sh
cd ${START_PATH}
rm -f download.sh
