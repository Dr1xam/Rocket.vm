#!/bin/bash
# Посилання на шматки
URL_Config="https://raw.githubusercontent.com/Dr1xam/Rocket.vm/refs/heads/main/config"

URL_INSTALL="https://raw.githubusercontent.com/Dr1xam/Rocket.vm/refs/heads/main/install.sh"

URL_MAKE_TEMPLATE="https://raw.githubusercontent.com/Dr1xam/Rocket.vm/refs/heads/main/make_template.sh"

URL_PART_A="https://github.com/Dr1xam/Rocket.vm/releases/download/v1.0/part_aa"
URL_PART_B="https://github.com/Dr1xam/Rocket.vm/releases/download/v1.0/part_ab"

echo "Завантаження частин..."
# -q --show-progress показує красиву смужку завантаження
wget -q --show-progress -O part_aa "$URL_PART_A"
wget -q --show-progress -O part_ab "$URL_PART_B"

# Перевірка, чи скачалися файли
if [ ! -f part_aa ] || [ ! -f part_ab ]; then
    echo "Помилка: Частини архіву не завантажені. Перевірте інтернет або посилання."
    rm part_*
    exit 1
fi

echo "Склеювання файлів..."
cat part_* > "$FINAL_FILE"

echo "Прибирання сміття (видалення частин)..."
rm part_*

wget -q --show-progress "$URL_ENV"


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
    exit 1
fi

chmod +x install.sh
./install.sh
