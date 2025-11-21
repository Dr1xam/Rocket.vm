#!/bin/bash
source install.conf
while VM_ID=$(shuf -i 100000000-999999999 -n 1); do
    qm status "$VM_ID" &>/dev/null || pct status "$VM_ID" &>/dev/null || break
done


cat > "$CONFIG_FILE" <<EOF
#Місце розташування машин
VM_TARGET_STORAGE="local-lvm"
# Конфігурація для Шаблону 
TEMPLATE_VM_ID=${VM_ID}
UBUNTU_BACKUP_TEMPLATE_NAME="vzdump-qemu-101.vma.zst"
MAKE_TEMPLATE_LOG_FILE="make_template.log"
EOF
