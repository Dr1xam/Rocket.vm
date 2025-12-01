#!/bin/bash
source install.conf
# Оголошуємо пустий масив
VM_IDS=()
IDS_COUNT=2
# Цикл: поки кількість елементів у масиві менша за 3
while [ "${#VM_IDS[@]}" -lt "$IDS_COUNT" ]; do
    # 1. Генеруємо кандидата
    CANDIDATE=$(shuf -i 100000000-999999999 -n 1)
    # 2. Перевірка в Proxmox (чи зайнятий ID системою)
    if qm status "$CANDIDATE" &>/dev/null || pct status "$CANDIDATE" &>/dev/null; then
        # ID зайнятий у Proxmox -> йдемо на нове коло
        continue
    fi
    # 3. Перевірка на дублікати в нашому масиві
    # (щоб не додати одне й те саме число двічі, якщо рандом так випаде)
    if [[ " ${VM_IDS[*]} " =~ " ${CANDIDATE} " ]]; then
        # ID вже є в списку -> йдемо на нове коло
        continue
    fi
    # 4. Якщо все чисто — додаємо в масив
    VM_IDS+=("$CANDIDATE")
done

AUTO_GW=$(ip route | grep default | awk '{print $3}' | head -n 1)
if [ -z "$AUTO_GW" ]; then
    echo " Не вдалося визначити шлюз автоматично."
    exit 1
fi

#пошук ip для машин 
WANTED_IPS_COUNT=$((IDS_COUNT + 1))  # Скільки IP нам треба
IPS=()          # Тут буде результат
# Отримуємо підмережу (наприклад, 192.168.1)
SUBNET=$(ip route | grep default | awk '{print $3}' | cut -d'.' -f1-3)
# Простий цикл від 50 до 250
for i in {50..250}; do
    CANDIDATE="$SUBNET.$i"
    # 1. Якщо пінг успішний АБО знайдено в конфігах -> пропускаємо
    (ping -c1 -W1 "$CANDIDATE" >/dev/null) || \
    (grep -r "$CANDIDATE" /etc/pve/qemu-server/ >/dev/null) && continue
    # 2. Якщо дійшли сюди - IP вільний. Додаємо в список.
    IPS+=("$CANDIDATE/24")
    # 3. Якщо назбирали достатньо - стоп
    [[ "${#IPS[@]}" -eq "$WANTED_IPS_COUNT" ]] && break
done

# Перевірка
if [[ "${#IPS[@]}" -lt "$WANTED_IPS_COUNT" ]]; then
    echo "Не вистачило вільних IP!"
    exit 1
fi

PROXMOX_IP=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

cat > "$CONFIG_FILE" <<EOF
VM_TARGET_STORAGE="local-lvm"
GATEWAY=${AUTO_GW}
PROXMOX_IP=${PROXMOX_IP}
# Конфігурація для Шаблону 
TEMPLATE_VM_ID=${VM_IDS[0]}
UBUNTU_BACKUP_TEMPLATE_NAME="vzdump-qemu-815898734-2025_11_24-17_42_12.vma.zst"
MAKE_TEMPLATE_LOG_FILE="./src/make_template.log"
#Коніфгурація для машини з рокетчатом
ROCKETCHAT_VM_ID="${VM_IDS[1]}"
ROCKETCHAT_VM_HOSTNAME="rocketchat"
ROCKETCHAT_DISK="50G"
ROCKETCHAT_VM_RAM="4096"
ROCKETCHAT_VM_CORES="4"
ROCKETCHAT_VM_IP="${IPS[0]}"
ROCKETCHAT_VM_BRIDGE="vmbr0"
ROCKETCHAT_VM_DNS="8.8.8.8"
DEPLOY_ROCKETCHAT_VM_LOG_FILE="deploy_rocketchat_vm.log"
ROCKETCHAT_ARCHIVE_NAME="Rocketchat.tar.gz"
ROCKETCHAT_VM_INSTALLATION_DIR="/root/offline_install"
DEPLOY_ROCKETCHAT_LOG_FILE="deploy_rocketchat.log"
EOF
