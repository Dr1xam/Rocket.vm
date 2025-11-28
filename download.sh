#!/bin/bash

# Посилання 
URL_SRC="https://github.com/Dr1xam/deployment-tool/releases/download/v0.2/src.tar.gz"
URL_PARTS="https://github.com/Dr1xam/deployment-tool/releases/download/v0.2/"
URL_ROCKETCHAT="https://github.com/Dr1xam/deployment-tool/releases/download/v0.2/Rocketchat.tar.gz"

# Шлях до фінального файлу бекапу

FINAL_FILE_NAME="vzdump-qemu-815898734-2025_11_24-17_42_12.vma.zst"
FINAL_FILE_DIRECTORY="/var/lib/vz/dump"
FINAL_FILE_PATH="${FINAL_FILE_DIRECTORY}/${FINAL_FILE_NAME}"

# початкова директорія 
START_PATH=$PWD

TEMP_DIR="download_buffer"

# --- ПЕРЕВІРКА ТА ВСТАНОВЛЕННЯ ARIA2 ---
if ! command -v aria2c &> /dev/null; then
    echo "Встановлення aria2 для багатопотокового завантаження..."
    apt-get update -qq && apt-get install -y -qq aria2 > /dev/null 2>&1
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

TOTAL_SIZE_GB="2.7"
TOTAL_BYTES=$(echo "scale=0; $TOTAL_SIZE_GB * 1073741824 / 1" | bc)

echo "Початок завантаження інсталятора"

# Вмикаємо зупинку при помилках
#set -e

# Створюємо тимчасову папку для буфера
mkdir -p "$TEMP_DIR"
ARIA_INPUT="$TEMP_DIR/input_urls.txt"

: > "$ARIA_INPUT"
# --- 1. ГЕНЕРАЦІЯ ФАЙЛУ ЗАВДАНЬ ДЛЯ ARIA2 ---
# aria2 підтримує формат: URL (новий рядок) out=filename
# А) Додаємо шматочки великого архіву
count=0
for url in $URL_LIST; do
    ((count++))
    part_name=$(printf "part_%03d" $count)
    echo "$url" >> "$ARIA_INPUT"
    echo "  out=$part_name" >> "$ARIA_INPUT"
done
# Б) Додаємо архів RocketChat
echo "$URL_ROCKETCHAT" >> "$ARIA_INPUT"
echo "  out=Rocketchat.tar.gz" >> "$ARIA_INPUT"
# В) Додаємо архів скриптів (src)
# Ми збережемо його як файл, а потім розпакуємо
echo "$URL_SRC" >> "$ARIA_INPUT"
echo "  out=src_code.tar.gz" >> "$ARIA_INPUT"



# 1. ЗАПУСК ARIA2 У ФОНІ (Мовчки, з оптимізацією диска)
# 1. ЗАПУСК ARIA2 У ФОНІ
aria2c -i "$ARIA_INPUT" \
       -d "$TEMP_DIR" \
       -j 5 -x 4 -s 4 \
       --file-allocation=none \
       --summary-interval=0 \
       --console-log-level=error \
       > /dev/null 2>&1 &

ARIA_PID=$!

# --- Ініціалізація змінних ---
START_TIME=$(date +%s)

# Лічильник для оновлення швидкості (починаємо з 1, щоб порахувати одразу)
INTERVAL_COUNTER=1

# Початкові значення
HUMAN_SPEED="--- MiB/s"
HUMAN_ETA="---"
# -----------------------------

# 2. ЦИКЛ ЗІ СМУЖКОЮ ПРОГРЕСУ
while kill -0 "$ARIA_PID" 2>/dev/null; do
    
    # 1. СТАБІЛЬНІ МЕТРИКИ (Оновлюються кожну 1 секунду)
    CURRENT_TIME=$(date +%s)
    CURRENT_BYTES=$(du -sb "$TEMP_DIR" 2>/dev/null | cut -f1)
    if [ -z "$CURRENT_BYTES" ]; then CURRENT_BYTES=0; fi

    # 1a. Час, що минув
    ELAPSED_TIME_SECONDS=$((CURRENT_TIME - START_TIME))
    EH=$((ELAPSED_TIME_SECONDS / 3600))
    EM=$(( (ELAPSED_TIME_SECONDS % 3600) / 60 ))
    ES=$(( ELAPSED_TIME_SECONDS % 60 ))
    HUMAN_ELAPSED_TIME=$(printf "%02d:%02d:%02d" $EH $EM $ES)

    # 1b. Прогрес
    if [ "$TOTAL_BYTES" -gt 0 ]; then PERCENT=$(( 100 * CURRENT_BYTES / TOTAL_BYTES )); else PERCENT=0; fi
    if [ "$PERCENT" -gt 100 ]; then PERCENT=100; fi
    CHARS=$(( PERCENT / 5 )); BAR=""; 
    for ((i=0; i<CHARS; i++)); do BAR="${BAR}#"; done
    for ((i=CHARS; i<20; i++)); do BAR="${BAR}."; done
    HUMAN_SIZE=$(du -sh "$TEMP_DIR" 2>/dev/null | cut -f1)

    # 2. ВОЛАТИЛЬНІ МЕТРИКИ (Оновлюються кожні 2 секунди)
    if [ "$INTERVAL_COUNTER" -le 1 ]; then 
        
        # 2a. Середня швидкість
        if [ "$ELAPSED_TIME_SECONDS" -gt 0 ]; then
             AVG_SPEED_BPS=$((CURRENT_BYTES / ELAPSED_TIME_SECONDS))
        else
             AVG_SPEED_BPS=1
        fi

        # 2b. ETA
        REMAINING_BYTES=$((TOTAL_BYTES - CURRENT_BYTES))
        if [ "$AVG_SPEED_BPS" -gt 0 ]; then
            ETA_SECONDS=$((REMAINING_BYTES / AVG_SPEED_BPS))
        else
            ETA_SECONDS=999999999
        fi

        # 2c. Форматування швидкості
        if [ "$AVG_SPEED_BPS" -ge 1048576 ]; then
            HUMAN_SPEED="$(echo "scale=2; $AVG_SPEED_BPS / 1048576" | bc) MiB/s"
        elif [ "$AVG_SPEED_BPS" -ge 1024 ]; then
            HUMAN_SPEED="$(echo "scale=1; $AVG_SPEED_BPS / 1024" | bc) KiB/s"
        else
            HUMAN_SPEED="${AVG_SPEED_BPS} B/s"
        fi

        # 2d. Форматування ETA
        if [ "$ETA_SECONDS" -lt 999999999 ]; then
            H=$((ETA_SECONDS / 3600))
            M=$(( (ETA_SECONDS % 3600) / 60 ))
            S=$(( ETA_SECONDS % 60 ))
            
            if [ $H -gt 0 ]; then
                 HUMAN_ETA=$(printf "%dч %02dхв %02dс" $H $M $S)
            elif [ $M -gt 0 ]; then
                 HUMAN_ETA=$(printf "%02dхв %02dс" $M $S)
            else
                 HUMAN_ETA=$(printf "%02dс" $S)
            fi
        else
            HUMAN_ETA="---"
        fi
        
        # Скидаємо лічильник на 2 секунди
        INTERVAL_COUNTER=2 
    fi

    # 3. ВИВІД
    echo -ne "\rЗавантаження: [${TOTAL_SIZE_GB} ${BAR}]/${HUMAN_SIZE} ${PERCENT}% | ${HUMAN_SPEED} | Час: ${HUMAN_ELAPSED_TIME} | ETA: ${HUMAN_ETA}   \033[K"
    
    sleep 1
    
    # 4. Зворотний відлік
    ((INTERVAL_COUNTER--))
done

# 3. ОТРИМАННЯ КОДУ ЗАВЕРШЕННЯ
wait "$ARIA_PID"
EXIT_CODE=$?

#echo -e "\rЗавантаження завершено!                               \n" # Очищаємо рядок прогресу

# --- 3. СКЛЕЮВАННЯ ТА РОЗПАКОВКА ---

# Склеюємо основний архів
cat "$TEMP_DIR"/part_* > "$FINAL_FILE_NAME"

# Переміщуємо RocketChat.tar.gz сюди
mv "$TEMP_DIR"/Rocketchat.tar.gz .

# Розпаковуємо скрипти (src) і видаляємо архів
tar -xzf "$TEMP_DIR"/src_code.tar.gz
# (Припускаємо, що архів містить папку src, tar розпакує її в поточну директорію)

# --- 4. ОЧИСТКА ---
rm -rf "$TEMP_DIR"

# --- 5. ФІНАЛЬНА ПЕРЕВІРКА ---
if [ ! -d "src" ] || [ ! -f "Rocketchat.tar.gz" ] || [ ! -s "$FINAL_FILE_NAME" ]; then
    echo "Помилка: Перевірка цілісності файлів не пройшла."
    
    # Видаляємо биті файли
    rm -rf "$TEMP_DIR"
    rm -f "$FINAL_FILE_NAME"
    rm -f "Rocketchat.tar.gz"
    rm -rf src
    
    cd "${START_PATH}"
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
