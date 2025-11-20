#!/bin/bash

# Посилання 
URL_CONFIG="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/main/config"
URL_INSTALL="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/main/install.sh"
URL_MAKE_TEMPLATE="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/main/make_template.sh"
URL_PARTS="https://github.com/Dr1xam/deployment-tool/releases/download/v1.0/"
URL_DELETE_SCRIPT="https://raw.githubusercontent.com/Dr1xam/deployment-tool/refs/heads/refactor-core/delete-script.sh"

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

echo "Початок завантаження архіву (єдиний потік)..."

# --- МАГІЯ ТУТ ---
# 1. wget отримує список URL і качає їх по черзі в stdout (-O -)
# 2. pv отримує дані, малює смужку (з розміром -s для відсотків)
# 3. > пише все відразу у фінальний файл
wget -q -O - $URL_LIST | pv -s $TOTAL_SIZE > "$FINAL_FILE_NAME"

# Перевірка статусу (pipefail гарантує помилку, якщо wget впаде)
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "Помилка завантаження!"
    rm "$FINAL_FILE_NAME"
    cd ${START_PATH}
    exit 1
fi

echo "Завантаження та склеювання завершено успішно."
#скрипт який все удалить + конфіг
wget -q --show-progress "$URL_CONFIG"
wget -q --show-progress "$URL_DELETE_SCRIPT"
#Перевірка чи завантажено скріпт 
if [ ! -f delete-script.sh ] || [ ! -f config ]; then
    echo "Помилка: Частини програми не завантажені. Перевірте інтернет або посилання."
    ./delete-script.sh
    cd ${START_PATH}
    rm download.sh
    exit 1
fi

#інсталяція інших файлів
wget -q --show-progress "$URL_MAKE_TEMPLATE"
#інсталтор в останю чергу
wget -q --show-progress "$URL_INSTALL"

#Перевірка чи завантажено скріпти
if [ ! -f make_template.sh ] || [ ! -f install.sh ]; then
    echo "Помилка: Частини програми не завантажені. Перевірте інтернет або посилання."
    ./delete-script.sh
    cd ${START_PATH}
    rm download.sh
    exit 1
fi

chmod +x install.sh
./install.sh

./delete-script.sh
cd ${START_PATH}
rm download.sh
