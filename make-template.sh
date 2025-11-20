source config

echo "Відновлення VM $NEW_VM_ID... (деталі пишуться в $TEMPLATE_LOG_FILE)"

set -o pipefail

# qmrestore розпаковує архів у віртуальну машину
# Запускаємо qmrestore
qmrestore "$UBUNTU_BACKUP_TEMPLATE_NAME" "$NEW_VM_ID" --storage "$TARGET_STORAGE" --unique --force 2>&1 | \
while IFS= read -r line; do
    case "$line" in
        *progress*)
            # ТІЛЬКИ НА ЕКРАН: гарна смужка
            echo -ne "\r$line\033[K"
            ;;
        *)
            # ВСЕ ІНШЕ: у файл логу (>> додає рядок в кінець файлу)
            echo "$line" >> "$TEMPLATE_LOG_FILE"
            ;;
    esac
done

# Перевірка результату
if [ $? -eq 0 ]; then
    echo -e "\n Відновлення завершено успішно."
    echo "Лог записано у файл: $TEMPLATE_LOG_FILE"
else
    echo "Виводжу повний лог помилки ($TEMPLATE_LOG_FILE):"
    echo "========================================================"
    
    # cat виведе весь файл від початку до кінця
    cat "$TEMPLATE_LOG_FILE"
    
    echo "========================================================"
    exit 1
fi

# (Опційно) Видалити великий склеєний файл, щоб звільнити місце
#rm -f "$UBUNTU_BACKUP_TEMPLATE_NAME"

echo "Готово! Ваш шаблон (ID: $NEW_VM_ID) створено і готовий до клонування."


