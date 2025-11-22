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

if [ $? -eq 0 ]; then
else
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

