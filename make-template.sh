source config

echo "Відновлення VM $NEW_VM_ID зі сховища $TARGET_STORAGE..."
# qmrestore розпаковує архів у віртуальну машину
qmrestore "$UBUNTU_BACKUP_TEMPLATE_NAME" "$NEW_VM_ID" --storage "$TARGET_STORAGE" --unique

# Перевіряємо, чи успішно пройшло відновлення (код 0 = успіх)
if [ $? -eq 0 ]; then
    echo "VM відновлена успішно."
else
    echo "Помилка відновлення VM! Можливо, ID $NEW_VM_ID вже зайнятий?"
    exit 1
fi

# (Опційно) Видалити великий склеєний файл, щоб звільнити місце
#rm -f "$UBUNTU_BACKUP_TEMPLATE_NAME"

echo "Готово! Ваш шаблон (ID: $NEW_VM_ID) створено і готовий до клонування."


