source vm.conf

echo "Відновлення VM $TEMPLATE_VM_ID (deploy-template) (деталі пишуться в $MAKE_TEMPLATE_LOG_FILE)"

set -o pipefail

# qmrestore розпаковує архів у віртуальну машину
# Запускаємо qmrestore
cd ..
qmrestore "$UBUNTU_BACKUP_TEMPLATE_NAME" "$TEMPLATE_VM_ID" --storage "$VM_TARGET_STORAGE" --unique --force 2>&1 | \
while IFS= read -r line; do
    case "$line" in
        *progress*)
            # ТІЛЬКИ НА ЕКРАН: гарна смужка
            echo -ne "\r$line\033[K"
            ;;
        *)
            # ВСЕ ІНШЕ: у файл логу (>> додає рядок в кінець файлу)
            echo "$line" >> "$MAKE_TEMPLATE_LOG_FILE"
            ;;
    esac
done


# Перевірка результату
if [ $? -eq 0 ]; then
    echo -e "\nВідновлення завершено успішно"
    echo "Лог відновлення записано у файл: $MAKE_TEMPLATE_LOG_FILE"
else
    echo "\n Виводжу повний лог помилки ($MAKE_TEMPLATE_LOG_FILE):"
    echo "========================================================"
    
    # cat виведе весь файл від початку до кінця
    cat "$MAKE_TEMPLATE_LOG_FILE"
    
    echo "========================================================"
    exit 1
fi
qm set "$TEMPLATE_VM_ID" --name deploy-template &> /dev/null

# (Опційно) Видалити великий склеєний файл, щоб звільнити місце
#rm -f "$UBUNTU_BACKUP_TEMPLATE_NAME"

cd src





