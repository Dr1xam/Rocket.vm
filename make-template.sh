source config

echo "Відновлення VM $NEW_VM_ID зі сховища $TARGET_STORAGE..."
# qmrestore розпаковує архів у віртуальну машину
qmrestore "$UBUNTU_BACKUP_TEMPLATE_NAME" "$NEW_VM_ID" --storage "$TARGET_STORAGE" --unique --force 2>&1 | \
while IFS= read -r line; do
    case "$line" in
        *progress*)
            # Якщо рядок містить "progress", виводимо його з поверненням курсору (\r)
            # \033[K очищає кінець рядка від сміття
            echo -ne "\r$line\033[K"
            ;;
        *ERROR*|*Error*|*fail*)
             # (Опціонально) Якщо є помилка, виводимо її, щоб знати, що сталося
             echo -e "\n$line"
             ;;
        *)
            # Усі інші рядки (CFG, WARNING, map, Logical volume...) ІГНОРУЄМО
            ;;
    esac
done

# Перевірка статусу
if [ $? -eq 0 ]; then
    echo -e "\n Відновлення завершено успішно."
else
    echo -e "\n Помилка під час відновлення."
    exit 1
fi

# (Опційно) Видалити великий склеєний файл, щоб звільнити місце
#rm -f "$UBUNTU_BACKUP_TEMPLATE_NAME"

echo "Готово! Ваш шаблон (ID: $NEW_VM_ID) створено і готовий до клонування."


