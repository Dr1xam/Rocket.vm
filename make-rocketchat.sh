source vm.conf

qm clone "$TEMPLATE_VM_ID" "$ROCKETCHAT_VM_ID" \
  --name "$ROCKETCHAT_VM_HOSTNAME" \
  --full 1 \
  --storage "$VM_TARGET_STORAGE" 

if [ $? -ne 0 ]; then
    echo " Критична помилка клонування! Перевірте, чи існує шаблон $TEMPLATE_VM_ID."
    exit 1
fi

qm set "$ROCKETCHAT_VM_ID" \
  --memory "$ROCKETCHAT_VM_RAM" \
  --cores "$ROCKETCHAT_VM_CORES" \
  --cpu cputype=host \
  --net0 virtio,bridge="$ROCKETCHAT_VM_BRIDGE" \
  --ipconfig0 ip="$ROCKETCHAT_VM_IP",gw="$GATEWAY" \
  --nameserver "$ROCKETCHAT_VM_DNS" \
  --onboot 1 

qm resize "$ROCKETCHAT_VM_ID" scsi0 "$ROCKETCHAT_DISK" 

