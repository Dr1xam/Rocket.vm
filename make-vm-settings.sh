#!/bin/bash
source install.conf
# Запитуємо данні
# read -p "Введіть ID машини: " VM_ID
# read -p "Введіть назву (hostname): " VM_NAME
# read -p "Кількість ядер CPU [2]: " CORES
# CORES=${CORES:-2} # Якщо пусто - буде 2
# read -p "Об'єм RAM (MB) [2048]: " MEMORY
# MEMORY=${MEMORY:-2048}
# read -p "IP адреса (CIDR, напр 192.168.1.50/24): " IP_ADDR



cat > "$CONFIG_FILE" <<EOF
#Місце розташування машин
VM_TARGET_STORAGE="local-lvm"
# Конфігурація для Шаблону 
TEMPLATE_VM_ID=105
UBUNTU_BACKUP_TEMPLATE_NAME="vzdump-qemu-101.vma.zst"
MAKE_TEMPLATE_LOG_FILE="make_template.log"
EOF
