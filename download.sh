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

# Налаштування для aria2: None або prealloc/falloc (залежить від системи)
# Якщо ви хочете уникнути sparse-файлів, спробуйте "prealloc" або "falloc" (при підтримці).
FILE_ALLOCATION="none"

# Назви частин архіву з бекапом убунту сервера
PART_PREFIX="part_archive_"
SUFFIXES=(
  aa ab ac ad ae af ag ah ai aj ak al am an ao ap aq ar as at au av
)

cd "${FINAL_FILE_DIRECTORY}" || { echo "Не вдалося перейти в ${FINAL_FILE_DIRECTORY}"; exit 1; }

# Формуємо список усіх URL в один рядок
URL_LIST=""
for suffix in "${SUFFIXES[@]}"; do
  URL_LIST="${URL_LIST} ${URL_PARTS}${PART_PREFIX}${suffix}"
done

# Попередньо відома загальна оцінка (використовується як резерв)
TOTAL_SIZE_GB="2.69"

# Функція для форматування bytes у человекопонятний вигляд
human_readable() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        printf "%.2fG" "$(awk -v b="$bytes" 'BEGIN{printf b/1073741824}')"
    elif [ "$bytes" -ge 1048576 ]; then
        printf "%.2fM" "$(awk -v b="$bytes" 'BEGIN{printf b/1048576}')"
    elif [ "$bytes" -ge 1024 ]; then
        printf "%.2fK" "$(awk -v b="$bytes" 'BEGIN{printf b/1024}')"
    else
        printf "%dB" "$bytes"
    fi
}

# Спроба визначити TOTAL_BYTES через HEAD-запити (Content-Length)
calculate_total_bytes_remote() {
    local sum=0
    local ok=true

    # Перелік URL-ів: частини + Rocketchat + src
    local urls=()
    for suffix in "${SUFFIXES[@]}"; do
        urls+=("${URL_PARTS}${PART_PREFIX}${suffix}")
    done
    urls+=("${URL_ROCKETCHAT}")
    urls+=("${URL_SRC}")

    for u in "${urls[@]}"; do
        # Таймаут невеликий, та слідкуємо за редіректами
        content_length=$(curl -sI -L --max-time 10 "$u" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2; exit}')
        if [ -z "$content_length" ]; then
            ok=false
            break
        fi
        # Обрізаємо пробіли
        content_length=$(echo "$content_length" | tr -d '[:space:]')
        # Перевірка що це число
        if ! [[ "$content_length" =~ ^[0-9]+$ ]]; then
            ok=false
            break
        fi
        sum=$((sum + content_length))
    done

    if [ "$ok" = true ]; then
        echo "$sum"
        return 0
    else
        echo "0"
        return 1
    fi
}

# Викликаємо спробу визначення загального розміру
REMOTE_TOTAL_BYTES=$(calculate_total_bytes_remote)
if [ "$REMOTE_TOTAL_BYTES" -gt 0 ]; then
    TOTAL_BYTES="$REMOTE_TOTAL_BYTES"
else
    # fallback: використовуємо конфігурований TOTAL_SIZE_GB
    TOTAL_BYTES=$(awk -v g="$TOTAL_SIZE_GB" 'BEGIN{printf "%d", g*1073741824}')
fi

echo "Початок завантаження інсталятора (total ≈ $(human_readable "$TOTAL_BYTES"))"

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
echo "$URL_SRC" >> "$ARIA_INPUT"
echo "  out=src_code.tar.gz" >> "$ARIA_INPUT"

# Trap для коректного завершення та очищення
on_exit() {
    local rc=$?
    if [ -n "$ARIA_PID" ]; then
        if kill -0 "$ARIA_PID" 2>/dev/null; then
            kill "$ARIA_PID" 2>/dev/null || true
            wait "$ARIA_PID" 2>/dev/null || true
        fi
    fi
    # Залишаємо тимчасові файли при успішному завершенні? тут видаляємо
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    exit $rc
}
trap on_exit EXIT INT TERM

# Запуск aria2
aria2c -i "$ARIA_INPUT" \
       -d "$TEMP_DIR" \
       -j 5 -x 4 -s 4 \
       --file-allocation="${FILE_ALLOCATION}" \
       --summary-interval=0 \
       --console-log-level=error \
       > /dev/null 2>&1 &

ARIA_PID=$!

# --- Ініціалізація змінних ---
START_TIME=$(date +%s)
INTERVAL_COUNTER=1
HUMAN_SPEED="---"
HUMAN_ETA="---"

# 2. ЦИКЛ ЗІ СМУЖКОЮ ПРОГРЕСУ
while kill -0 "$ARIA_PID" 2>/dev/null; do

    CURRENT_TIME=$(date +%s)
    # Сумуємо реальні розміри файлів (включаючи часткові завантаження),
    # виключаємо служебні .aria2 файли, щоб не рахувати метаданa.
    CURRENT_BYTES=$(find "$TEMP_DIR" -type f ! -name '*.aria2' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
    if [ -z "$CURRENT_BYTES" ]; then CURRENT_BYTES=0; fi

    # Час, що минув
    ELAPSED_TIME_SECONDS=$((CURRENT_TIME - START_TIME))
    EH=$((ELAPSED_TIME_SECONDS / 3600))
    EM=$(((ELAPSED_TIME_SECONDS % 3600) / 60))
    ES=$((ELAPSED_TIME_SECONDS % 60))
    HUMAN_ELAPSED_TIME=$(printf "%02d:%02d:%02d" $EH $EM $ES)

    # Прогрес (цілочисельний)
    if [ "$TOTAL_BYTES" -gt 0 ]; then
        PERCENT=$((100 * CURRENT_BYTES / TOTAL_BYTES))
    else
        PERCENT=0
    fi
    if [ "$PERCENT" -gt 100 ]; then PERCENT=100; fi

    CHARS=$((PERCENT / 5))
    BAR=""
    for ((i=0; i<CHARS; i++)); do BAR="${BAR}#"; done
    for ((i=CHARS; i<20; i++)); do BAR="${BAR}."; done

    # Форматований розмір на екрані (з поточних байтів)
    HUMAN_SIZE=$(human_readable "$CURRENT_BYTES")
    TOTAL_HUMAN=$(human_readable "$TOTAL_BYTES")

    # Оновлюємо швидкість та ETA кожні 2 секунди
    if [ "$INTERVAL_COUNTER" -le 1 ]; then
        if [ "$ELAPSED_TIME_SECONDS" -gt 0 ]; then
            AVG_SPEED_BPS=$((CURRENT_BYTES / ELAPSED_TIME_SECONDS))
        else
            AVG_SPEED_BPS=0
        fi

        REMAINING_BYTES=$((TOTAL_BYTES - CURRENT_BYTES))
        if [ "$AVG_SPEED_BPS" -gt 0 ]; then
            ETA_SECONDS=$((REMAINING_BYTES / AVG_SPEED_BPS))
        else
            ETA_SECONDS=999999999
        fi

        # Форматування швидкості
        if [ "$AVG_SPEED_BPS" -ge 1048576 ]; then
            HUMAN_SPEED="$(awk -v b="$AVG_SPEED_BPS" 'BEGIN{printf "%.2f MiB/s", b/1048576}')"
        elif [ "$AVG_SPEED_BPS" -ge 1024 ]; then
            HUMAN_SPEED="$(awk -v b="$AVG_SPEED_BPS" 'BEGIN{printf "%.1f KiB/s", b/1024}')"
        else
            HUMAN_SPEED="${AVG_SPEED_BPS} B/s"
        fi

        # Форматування ETA
        if [ "$ETA_SECONDS" -lt 999999999 ]; then
            H=$((ETA_SECONDS / 3600))
            M=$(((ETA_SECONDS % 3600) / 60))
            S=$((ETA_SECONDS % 60))

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

        INTERVAL_COUNTER=2
    fi

    # Вивід прогресу
    printf "\rЗавантаження: %8s / %8s  [%s] %3d%% | %8s | Час: %s | ETA: %s   \033[K" \
        "$HUMAN_SIZE" "$TOTAL_HUMAN" "$BAR" "$PERCENT" "$HUMAN_SPEED" "$HUMAN_ELAPSED_TIME" "$HUMAN_ETA"

    sleep 1
    ((INTERVAL_COUNTER--))
done

# Чекаємо завершення aria2
wait "$ARIA_PID"
EXIT_CODE=$?

echo -e "\nЗавантаження завершено"

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
    
    rm -rf "$TEMP_DIR"
    rm -f "$FINAL_FILE_NAME"
    rm -f "Rocketchat.tar.gz"
    rm -rf src
    
    cd "${START_PATH}" || true
    exit 1
fi

cd src || true
chmod +x install.sh
chmod +x make-vm-settings.sh
chmod +x delete-script.sh
chmod +x make-template.sh
chmod +x make-rocketchat.sh
./install.sh

cd "${START_PATH}" || true
rm -f download.sh
