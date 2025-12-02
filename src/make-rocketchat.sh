source vm.conf

# Очищаємо старий лог (створюємо новий)
echo "Клонування VM $ROCKETCHAT_VM_ID (rocketchat) (деталі пишуться в $DEPLOY_ROCKETCHAT_VM_LOG_FILE)"

# Вмикаємо pipefail, щоб помилка qm clone передавалася через пайп
set -o pipefail

# 1. КЛОНУВАННЯ (Довгий процес з прогрес-баром)
qm clone "$TEMPLATE_VM_ID" "$ROCKETCHAT_VM_ID" \
  --name "$ROCKETCHAT_VM_HOSTNAME" \
  --full 1 \
  --storage "$VM_TARGET_STORAGE" 2>&1 | \
while IFS= read -r line; do
    case "$line" in
        # qm clone пише "transferred ...", тому ловимо це слово
        *transferred*|*%)
            # ТІЛЬКИ НА ЕКРАН: перезапис рядка
            echo -ne "\r$line\033[K"
            ;;
        *)
            # ВСЕ ІНШЕ: у лог
            echo "$line" >> "$DEPLOY_ROCKETCHAT_VM_LOG_FILE"
            ;;
    esac
done

# Перевірка результату клонування
if [ $? -ne 0 ]; then
    echo -e "\nПОМИЛКА КЛОНУВАННЯ ROKCKETCHAT! Дивіться лог ($DEPLOY_ROCKETCHAT_VM_LOG_FILE):"
    echo "========================================================"
    cat "$DEPLOY_ROCKETCHAT_VM_LOG_FILE"
    echo "========================================================"
    exit 1
fi

# 2. НАЛАШТУВАННЯ (Швидкий процес)

# Тут ми просто пишемо все в лог, щоб не смітити на екрані
qm set "$ROCKETCHAT_VM_ID" \
  --ide2 local-lvm:cloudinit \
  --memory "$ROCKETCHAT_VM_RAM" \
  --cores "$ROCKETCHAT_VM_CORES" \
  --cpu cputype=host \
  --net0 virtio,bridge="$ROCKETCHAT_VM_BRIDGE" \
  --ipconfig0 ip="${ROCKETCHAT_VM_IP}",gw="$GATEWAY" \
  --nameserver "$ROCKETCHAT_VM_DNS" \
  --onboot 1 \
  --agent 1 >> "$DEPLOY_ROCKETCHAT_VM_LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "ПОМИЛКА"
    echo "Деталі в лозі: $DEPLOY_ROCKETCHAT_VM_LOG_FILE"
    exit 1
fi

# 3. РОЗШИРЕННЯ ДИСКА
qm resize "$ROCKETCHAT_VM_ID" scsi0 "$ROCKETCHAT_DISK" >> "$DEPLOY_ROCKETCHAT_VM_LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
        echo -e "\nКлонування завершено успішно."
    echo "Лог клонування записано у файл: $DEPLOY_ROCKETCHAT_VM_LOG_FILE"
else
    echo "ПОМИЛКА"
    cat "$DEPLOY_ROCKETCHAT_VM_LOG_FILE"
    exit 1
fi

echo "Запускаю VM $ROCKETCHAT_VM_ID (rocketchat)"
qm set "$ROCKETCHAT_VM_ID" --agent 1 > /dev/null 2>&1 
qm start "$ROCKETCHAT_VM_ID"

echo -n "Очікую повної готовності VM $ROCKETCHAT_VM_ID (rocketchat)"

# Налаштування тайм-ауту (щоб не чекати вічно, якщо машина зависла)
MAX_WAIT_SECONDS=300
TIMER=0

# Цикл: поки команда qm agent ping повертає помилку — чекаємо
while ! qm agent "$ROCKETCHAT_VM_ID" ping > /dev/null 2>&1; do
    
    # Перевірка на тайм-аут
    if [ "$TIMER" -ge "$MAX_WAIT_SECONDS" ]; then
        echo -e "\nТайм-аут! VM не запустила QEMU Agent за $MAX_WAIT_SECONDS секунд."
        exit 1
    fi

    # Чекаємо 1 секунду
    sleep 1
    ((TIMER++))
    echo -n "."
done

echo -e "\nVM $ROCKETCHAT_VM_ID (rocketchat) завантажена! (Час запуску: ${TIMER}с)"


#Встановлення рокетчату
set -o pipefail
cd ..
# Перевірка наявності архіву
if [ ! -f "$ROCKETCHAT_ARCHIVE_NAME" ]; then
    echo "Помилка: Файл $ROCKETCHAT_ARCHIVE_NAME не знайдено!"
    exit 1
fi

echo "Вcтановлення Rocketсhat на VM $ROCKETCHAT_VM_ID (rocketchat)"


# 1. ЗАПУСКАЄМО ВЕБ-СЕРВЕР (з захистом cleanup)
python3 -m http.server 8888 > /dev/null 2>&1 &
SERVER_PID=$!
sleep 2

# Функція очистки: вб'є сервер при виході зі скрипта (успішному чи ні)
cleanup() {
    kill $SERVER_PID 2>/dev/null
}
trap cleanup EXIT

# 2. КОМАНДА ДЛЯ ВІРТУАЛКИ
# set -e зупинить виконання при першій же помилці
cat > install_rocketchat_in_vm.sh <<EOF
#!/bin/bash
set -x
set -e

# Створюємо папку
mkdir -p $ROCKETCHAT_VM_INSTALLATION_DIR
cd $ROCKETCHAT_VM_INSTALLATION_DIR

# Скачуємо
echo "Downloading..."
wget -qO - http://$PROXMOX_IP:8888/$ROCKETCHAT_ARCHIVE_NAME | tar -xz

# Заходимо в папку (якщо вона є)
[ -d 'Rocketchat' ] && cd Rocketchat

# Встановлюємо Snap
echo "Installing..."
snap ack core20_*.assert
snap install core20_*.snap

snap ack snapd_*.assert
snap install snapd_*.snap

snap ack rocketchat-server_*.assert
snap install rocketchat-server_*.snap

# Прибираємо за собою
cd /root
rm -rf $ROCKETCHAT_VM_INSTALLATION_DIR
EOF

CMD="wget -qO /root/install.sh http://$PROXMOX_IP:8888/install_rocketchat_in_vm.sh && chmod +x /root/install.sh && /root/install.sh > /dev/null 2>&1"
EXEC_RESPONSE=$(qm guest exec "$ROCKETCHAT_VM_ID" --timeout 1 -- bash -c "$CMD" 2>&1)

# 3. ВИТЯГУЄМО PID
PID=$(echo "$EXEC_RESPONSE" | grep -oP '"pid"\s*:\s*\K\d+')

if [ -z "$PID" ]; then
    echo "Помилка запуску! Агент не повернув PID."
    echo "Відповідь: $EXEC_RESPONSE"
    exit 1
fi

# 4. ЦИКЛ ОЧІКУВАННЯ
while true; do
    # 1. Отримуємо статус (і stdout, і stderr)
    STATUS_JSON=$(qm guest exec-status "$ROCKETCHAT_VM_ID" "$PID" 2>&1)

    # --- УМОВА 1: Це взагалі JSON? (Перевірка на помилку/текст) ---
    # Якщо у відповіді НЕМАЄ слова "exited", значить це якась текстова помилка
    if ! echo "$STATUS_JSON" | grep -q "exited"; then
        echo -e "\n КРИТИЧНА ПОМИЛКА СТАТУСУ!"
        echo "   Proxmox повернув не JSON, а текст:"
        echo "   >> $STATUS_JSON"
        exit 1
    fi

    # --- УМОВА 2: Процес ще працює? ("exited": 0) ---
    if echo "$STATUS_JSON" | grep -qP '"exited"\s*:\s*0'; then
        echo -n "*"
        sleep 2
        continue  # Йдемо на наступне коло циклу
    fi

    # --- УМОВА 3: Процес завершився ("exited": 1) ---
    if echo "$STATUS_JSON" | grep -qP '"exited"\s*:\s*1'; then
        
        # Витягуємо код виходу
        EXIT_CODE=$(echo "$STATUS_JSON" | grep -oP '"exitcode"\s*:\s*\K\d+')

        if [ "$EXIT_CODE" == "0" ]; then
            echo -e "\nRocketchat встановлено"
            break # Виходимо з циклу, все добре
        else
            echo -e "\n ПОМИЛКА ІНСТАЛЯЦІЇ! Код виходу: $EXIT_CODE"
            # (Опціонально) Спробувати вивести текст помилки з JSON, якщо він там є
            # echo "$STATUS_JSON"
            exit 1
        fi
    fi
done

echo "" # Новий рядок
rm -f install_rocketchat_in_vm.sh
cd src

#________________________________________________________________________
# 3. ФІНАЛЬНА ПЕРЕВІРКА СТАТУСУ
# echo " Перевіряю статус сервісу..."
# sleep 5 # Даємо трохи часу на ініціалізацію snapd

# # Перевіряємо, чи сервіс 'active'
# STATUS_CHECK=$(qm guest exec "$VM_ID" -- snap services rocketchat-server | grep "active")

# if [[ -n "$STATUS_CHECK" ]]; then
#     echo " УСПІХ! Rocket.Chat встановлено і він АКТИВНИЙ."
#     # Виводимо порти для певностіhttps://gemini.google.com/app/57b137c81f8e7130?hl=ru
#     qm guest exec "$VM_ID" -- ss -tulpn | grep 3000
# else
#     echo " Увага: Установка пройшла, але сервіс не активний. Перевірте логи:"
#     echo "   qm guest exec $VM_ID -- snap logs rocketchat-server"
# fi

