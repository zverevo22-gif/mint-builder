#!/usr/bin/env bash
# ============================================================================
#  Стадия 05 - упаковка изменённой live-ФС обратно в casper/filesystem.squashfs
#  и обновление служебных файлов casper  (filesystem.size, манифесты).
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

require_root

[ -d "$SQUASH_DIR" ] || die "Нет распакованной live-ФС ($SQUASH_DIR). Выполните стадии 03 и/или 04."

# --- Контроль: rootfs обязан быть НАСТОЯЩЕЙ распакованной системой ------------
# (защита от упаковки в squashfs частично очищенного / пустого каталога,
#  из-за чего casper не находит init и загрузка падает с 'No init found').
SQUASH_INODES=$(find "$SQUASH_DIR" -xdev 2>/dev/null | wc -l)
SQUASH_BYTES=$(du -sb "$SQUASH_DIR" 2>/dev/null | cut -f1)
c_info "Проверка rootfs: $SQUASH_DIR (inode: $SQUASH_INODES, размер: $SQUASH_BYTES байт)"
for _must in etc/os-release usr/bin/bash var/lib/dpkg/status; do
  [ -e "$SQUASH_DIR/$_must" ] || die "НЕПРАВИЛЬНЫЙ ROOTFS: нет файла /$_must в $SQUASH_DIR. Запустите стадию 03 заново."
done
if [ "$SQUASH_INODES" -lt 50000 ] || [ "$SQUASH_BYTES" -lt 1024000000 ]; then
  die "Rootfs подозрительно мал (inode=$SQUASH_INODES, $SQUASH_BYTES байт). В нём нет полной live-системы - упаковка отменена. Удалите $WORKDIR и запустите сборку заново."
fi

# --- Сжатие: берём алгоритм исходного образа (xz / zstd / gzip...), иначе xz ---
COMP=$(detect_squashfs_compression)
case "$COMP" in
  zstd)  MKFS_OPTS="-comp zstd"                       ;;
  gzip)  MKFS_OPTS="-comp gzip"                       ;;
  lzo)   MKFS_OPTS="-comp lzo"                        ;;
  *)     COMP="xz"; MKFS_OPTS="-comp xz"              ;;
esac
c_info "Сжимаем squashfs алгоритмом: $COMP"

rm -f "$SQUASH_FILE"
# -b 128K = штатный размер блока исходного образа (не меняем геометрию squashfs)
mksquashfs "$SQUASH_DIR" "$SQUASH_FILE" \
  -no-progress -noappend -b 128K $MKFS_OPTS \
  || die "Не удалось собрать squashfs."

# Контроль: файл обязан читаться
unsquashfs -s "$SQUASH_FILE" >/dev/null 2>&1 || die "Собраный squashfs не читается - что-то не так."

# --- Размер ФС (байты) для casper ---------------------------------------------
SIZE=$(du -sb "$SQUASH_DIR" | cut -f1)
printf '%s\n' "$SIZE" > "$ISO_DIR/casper/filesystem.size"

# --- Манифесты пакетов (используются при установке и в live-режиме) ------------
c_info "Пересоздаём casper/filesystem.manifest ..."
dpkg-query --admindir "$SQUASH_DIR/var/lib/dpkg" \
  -W --showformat='${Package} ${Version}\n' \
  > "$ISO_DIR/casper/filesystem.manifest" 2>/dev/null \
  || c_warn "Не удалось пересоздать filesystem.manifest (старый оставлен)."

# Список удалённых пакетов (для инсталлятора)
read_list "$PACKAGES_REMOVE_LIST" > "$ISO_DIR/casper/filesystem.manifest-remove" 2>/dev/null || true
read_list "$PACKAGES_ADD_LIST"    > "$ISO_DIR/casper/filesystem.manifest-add"    2>/dev/null || true

rm -f "$ISO_DIR/casper/filesystem.manifest-desktop" 2>/dev/null || true
if [ -n "$(read_list "$PACKAGES_ADD_LIST")" ]; then
   dpkg-query --admindir "$SQUASH_DIR/var/lib/dpkg" \
     -W --showformat='${Package} ${Version}\n' \
     > "$ISO_DIR/casper/filesystem.manifest-desktop" 2>/dev/null || true
fi

ls -lh "$SQUASH_FILE"
c_ok "Стадия 05 завершена: live-ФС упакована."