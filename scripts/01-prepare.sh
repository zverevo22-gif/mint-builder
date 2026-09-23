#!/usr/bin/env bash
# ============================================================================
#  Стадия 01 - проверка окружения и исходных данных
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

require_root
mkdir -p "$WORKDIR"

c_info "Проверка необходимых программ..."
for cmd in xorriso unsquashfs mksquashfs mount umount dpkg dpkg-query rsync find sed stat; do
  require_cmd "$cmd"
done

# MBR-загрузчик для гибридного ISO (пакет isolinux / syslinux-common)
if ! detect_isohdpfx; then
  c_warn "Не найден isohdpfx.bin (нужен для гибридной записи ISO на флешку)."
  c_warn "Установите пакет:  sudo apt install isolinux   (или syslinux-common)"
fi

# Исходный ISO
[ -f "$SOURCE_ISO" ] || die "Исходный ISO не найден: $SOURCE_ISO
=> укажите правильный путь в config/build.conf (поле SOURCE_ISO)."

# Если это не ISO-файл - сразу предупредим
file "$SOURCE_ISO" | grep -qi 'iso 9660\|FAT\|DOS' || \
  c_warn "Файл '$SOURCE_ISO' не похож на ISO-образ (ISO 9660), продолжаем на свой риск."

# Свободное место
ISO_SIZE=$(stat -c %s "$SOURCE_ISO")
FREE=$(df -B1 --output=avail "$WORKDIR" 2>/dev/null | tail -1)
NEED=$(( ISO_SIZE * 3 + 2147483648 ))   # образ x3 + 2 ГБ запаса
if [ -n "$FREE" ] && [ "$FREE" -lt "$NEED" ]; then
  c_warn "На диске мало места: доступно ~$(( FREE/1024/1024/1024 )) ГБ, нужно ~$(( NEED/1024/1024/1024 )) ГБ."
  c_warn "Перенесите WORKDIR на диск с свободным местом."
fi

c_info "Исходный ISO : $SOURCE_ISO"
c_info "Рабочий каталог: $WORKDIR"
c_info "Будет собран   : $OUTPUT_ISO"
c_ok "Стадия 01 завершена."