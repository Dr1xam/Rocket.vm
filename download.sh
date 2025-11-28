#!/bin/bash

# Посилання 
URL_SRC="https://github.com/Dr1xam/deployment-tool/releases/download/v0.2/src.tar.gz"
URL_PARTS="https://github.com/Dr1xam/deployment-tool/releases/download/v0.2/"
URL_ROCKETCHAT="https://github.com/Dr1xam/deployment-tool/releases/download/v0.2/Rocketchat.tar.gz"

# Шлях до фінального файлу бекапу

FINAL_FILE_NAME="vzdump-qemu-815898734-2025_11_24-17_42_12.vma.zst"
FINAL_FILE_DIRECTORY="/var/lib/vz/dump"
FINAL_FILE_PATH="${FINAL_FILE_DIRECTORY}/${FINAL_FILE_NAME}"

# Приблизний розмір архіву для коректної смужки (21 файл по 100мб + 1 шматок ~84мб)
# Це потрібно, щоб pv показував саме відсотки (%). Якщо розмір зміниться, смужка просто дійде до кінця раніше або пізніше.
TOTAL_SIZE="2181m"

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


# # Завантаження + Склеювання (однією смужкою)
# wget -q -O - $URL_LIST | pv -s $TOTAL_SIZE > "$FINAL_FILE_NAME"

# # Перевірка статусу (pipefail гарантує помилку, якщо wget впаде)
# if [ ${PIPESTATUS[0]} -ne 0 ]; then
#     echo "Помилка завантаження!"
#     rm -f "$FINAL_FILE_NAME"
#     cd ${START_PATH}
#     exit 1
# fi

wget -q  -O - $URL_SRC | tar -xz

#Перевірка чи завантажено скріпти
if  [ ! -d src ] || [ ! -f Rocketchat.tar.gz ]; then
    echo "Помилка: Не всі файли завантажено."
    rm -f ${FINAL_FILE_NAME}
    rm -f Rocketchat.tar.gz
    cd ${START_PATH}
    rm -f download.sh
    exit 1
fi

cd src
chmod +x install.sh
chmod +x make-vm-settings.sh
chmod +x delete-script.sh
chmod +x make-template.sh
chmod +x make-rocketchat.sh
#./install.sh

#./delete-script.sh
cd ${START_PATH}
rm -f download.sh
