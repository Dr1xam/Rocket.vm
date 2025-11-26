source vm.conf

# Очищаємо старий лог (створюємо новий)
echo "Клонування VM $ROCKETCHAT_VM_ID... (деталі пишуться в $DEPLOY_ROCKETCHAT_VM_LOG_FILE)"

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
if [ $? -eq 0 ]; then
    echo -e "\n Клонування завершено успішно."
else
    echo -e "\n ПОМИЛКА КЛОНУВАННЯ ROKCKETCHAT! Дивіться лог ($DEPLOY_ROCKETCHAT_VM_LOG_FILE):"
    echo "========================================================"
    cat "$DEPLOY_ROCKETCHAT_VM_LOG_FILE"
    echo "========================================================"
    exit 1
fi

# 2. НАЛАШТУВАННЯ (Швидкий процес)

# Тут ми просто пишемо все в лог, щоб не смітити на екрані
qm set "$ROCKETCHAT_VM_ID" \
  --memory "$ROCKETCHAT_VM_RAM" \
  --cores "$ROCKETCHAT_VM_CORES" \
  --cpu cputype=host \
  --net0 virtio,bridge="$ROCKETCHAT_VM_BRIDGE" \
  --ipconfig0 ip="$ROCKETCHAT_VM_IP",gw="$GATEWAY" \
  --nameserver "$ROCKETCHAT_VM_DNS" \
  --onboot 1 >> "$DEPLOY_ROCKETCHAT_VM_LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "ПОМИЛКА"
    echo "Деталі в лозі: $DEPLOY_ROCKETCHAT_VM_LOG_FILE"
    exit 1
fi

# 3. РОЗШИРЕННЯ ДИСКА
echo -n "Розширюю диск до $ROCKETCHAT_DISK... "

qm resize "$ROCKETCHAT_VM_ID" scsi0 "$ROCKETCHAT_DISK" >> "$DEPLOY_ROCKETCHAT_VM_LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
        echo -e "\nКлонування завершено успішно."
    echo "Лог відновлення записано у файл: $DEPLOY_ROCKETCHAT_VM_LOG_FILE"
else
    echo "ПОМИЛКА"
    cat "$DEPLOY_ROCKETCHAT_VM_LOG_FILE"
    exit 1
fi

echo "Запускаю VM $ROCKETCHAT_VM_ID..."
qm set "$ROCKETCHAT_VM_ID" --agent 1
qm start "$ROCKETCHAT_VM_ID"

echo -n "Очікую повної готовності системи..."

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

echo -e "\nСистема завантажена! (Час запуску: ${TIMER}с)"


#Встановлення рокетчату
set -o pipefail

# Перевірка наявності архіву
if [ ! -f "$ROCKETCHAT_ARCHIVE_NAME" ]; then
    echo "Помилка: Файл $ROCKETCHAT_ARCHIVE_NAME не знайдено!"
    exit 1
fi

echo "Починаю установку Rocketсhat на VM $ROCKETCHAT_VM_ID..."

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
echo "Виконую інсталяцію rocketchat на VM...(деталі пишуться в $DEPLOY_ROCKETCHAT_LOG_FILE)"
cat > install_rocketchat_in_vm.sh <<EOF
#!/bin/bash
# Пишемо логи у файл всередині VM
exec > /tmp/vm_debug.log 2>&1
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
echo "Done!"
EOF
CMD="wget -qO /root/install.sh http://$PROXMOX_IP:8888/install_rocketchat_in_vm.sh && chmod +x /root/install.sh && /root/install.sh > /dev/null 2>&1"
EXEC_OUTPUT=$(qm guest exec "$ROCKETCHAT_VM_ID" -- bash -c "$CMD")

# 2. Витягуємо PID процесу (тихо)
PID=$(echo "$EXEC_OUTPUT" | grep -oP '(?<="pid":)\d+')

# Перевірка, чи взагалі запустилося
if [ -z "$PID" ]; then
    echo "Критична помилка: Агент не відповів."
    exit 1
fi

# 3. Тихо чекаємо завершення
while true; do
    # Запитуємо статус
    STATUS=$(qm guest exec-status "$ROCKETCHAT_VM_ID" "$PID")
    
    # Перевіряємо, чи процес завершився ("exited":1)
    if echo "$STATUS" | grep -q '"exited":1'; then
        # Перевіряємо код виходу ("exitcode":0 - це успіх)
        if echo "$STATUS" | grep -q '"exitcode":0'; then
            qm guest exec "$ROCKETCHAT_VM_ID" -- bash -c "cat /tmp/vm_debug.log && rm /tmp/vm_debug.log" > "$DEPLOY_ROCKETCHAT_LOG_FILE"
            echo "Інсталяція завершена успішно!"
            break
        else
            # ПОМИЛКА (Тільки зараз щось виводимо)
            qm guest exec "$ROCKETCHAT_VM_ID" -- bash -c "cat /tmp/vm_debug.log && rm /tmp/vm_debug.log" > "$DEPLOY_ROCKETCHAT_LOG_FILE"
            echo -e "\n ПОМИЛКА: Інсталяція впала! Дивіться лог ($DEPLOY_ROCKETCHAT_LOG_FILE):"
            echo "========================================================"
            cat "$DEPLOY_ROCKETCHAT_LOG_FILE"
            echo "========================================================"
            rm -f install_rocketchat_in_vm.sh
            exit 1
        fi
    fi
    # Пауза перед наступною перевіркою
    sleep 2
done

rm -f install_rocketchat_in_vm.sh


#________________________________________________________________________
# 3. ФІНАЛЬНА ПЕРЕВІРКА СТАТУСУ
# echo " Перевіряю статус сервісу..."
# sleep 5 # Даємо трохи часу на ініціалізацію snapd

# # Перевіряємо, чи сервіс 'active'
# STATUS_CHECK=$(qm guest exec "$VM_ID" -- snap services rocketchat-server | grep "active")

# if [[ -n "$STATUS_CHECK" ]]; then
#     echo " УСПІХ! Rocket.Chat встановлено і він АКТИВНИЙ."
#     # Виводимо порти для певності
#     qm guest exec "$VM_ID" -- ss -tulpn | grep 3000
# else
#     echo " Увага: Установка пройшла, але сервіс не активний. Перевірте логи:"
#     echo "   qm guest exec $VM_ID -- snap logs rocketchat-server"
# fi

