#!/bin/bash
# Посилання на шматки
URL_CONFIG="https://raw.githubusercontent.com/Dr1xam/Rocket.vm/refs/heads/main/config"

URL_INSTALL="https://raw.githubusercontent.com/Dr1xam/Rocket.vm/refs/heads/main/install.sh"

URL_MAKE_TEMPLATE="https://raw.githubusercontent.com/Dr1xam/Rocket.vm/refs/heads/main/make_template.sh"

BASE_URL="https://github.com/Dr1xam/Rocket.vm/releases/download/v1.0/"

PART_PREFIX="part_archive_"

SUFFIXES=(
  aa ab ac ad ae af ag ah ai aj ak al am an ao ap aq ar as at au av
)

echo "Завантаження конфігурацій..."
wget -q --show-progress "$URL_CONFIG"

source config

cd ${FINAL_FILE_DIRECTORY}

# for suffix in "${SUFFIXES[@]}"; do
#   # Формуємо повне ім'я файлу на сервері (наприклад, part_archive_aa)
#   REMOTE_NAME="${PART_PREFIX}${suffix}"
  
#   # Формуємо URL
#   URL="${BASE_URL}${REMOTE_NAME}"
  
#   # Формуємо локальне ім'я файлу (наприклад, part_aa)
#   LOCAL_NAME="${PART_PREFIX}${suffix}"
  
#   echo "Завантаження ${LOCAL_NAME}..."

#   # Виконуємо завантаження
#   wget -q --show-progress -O "$LOCAL_NAME" "$URL"
  
#   # Перевірка, чи успішно скачався файл
#   if [ $? -ne 0 ]; then
#     echo "Помилка завантаження файлу ${LOCAL_NAME}. Перевірте інтернет або посилання."
#     rm ${PART_PREFIX}*
#     cd ${START_PATH}
#     rm config
#     exit 1
#   fi
# done

echo "Усі частини завантажено успішно."

# --- СКЛЕЮВАННЯ ---

echo "Склеювання частин у файл: ${FINAL_FILE_NAME}..."

# cat part_archive_a* склеїть їх у правильному алфавітному порядку (aa, ab, ac, ...)
cat $PART_PREFIX* > $FINAL_FILE_NAME

if [ $? -eq 0 ]; then
  echo "Склеювання завершено. Файл ${FINAL_FILE_NAME} готовий."
else
  echo "Помилка під час склеювання файлів."
  rm ${PART_PREFIX}*
  cd ${START_PATH}
  rm config
  exit 1
fi

#rm ${PART_PREFIX}*

cd ${START_PATH}
wget -q --show-progress "$URL_MAKE_TEMPLATE"

#інсталтор в останю чергу
wget -q --show-progress "$URL_INSTALL"

#Перевірка чи завантажено скріпти
if [ ! -f config ] || [ ! -f make_template.sh ] || [ ! -f install.sh ]; then
    echo "Помилка: Частини програми не завантажені. Перевірте інтернет або посилання."
    rm config
    rm make_template.sh
    rm install.sh
    rm download.sh
    rm /var/lib/vz/dump/template.vma.zst
    exit 1
fi

chmod +x install.sh
./install.sh

rm config
rm make_template.sh
rm install.sh
rm download.sh
rm /var/lib/vz/dump/template.vma.zst
