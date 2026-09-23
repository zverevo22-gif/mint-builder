#!/usr/bin/env bash
# ============================================================================
#  Стадия 06 - сборка итогового гибридного ISO (BIOS + UEFI).
#
#  Скрипт сам определяет компоновку загрузки исходного образа:
#    * isolinux-стиль (Linux Mint 21):  isolinux/isolinux.bin
#    * grub-стиль (новые Ubuntu/Mint):  boot/grub/i386-pc/eltorito.img
#    * EFI:  efi.img  или  boot/grub/efi.img
#  Полученный ISO записывается на флешки командой dd без доп. утилит.
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

[ -d "$ISO_DIR" ] || die "Нет каталога ISO ($ISO_DIR). Выполните стадию 02."
[ -f "$SQUASH_FILE" ] || die "Нет casper/filesystem.squashfs. Выполните стадию 05."

# --- MBR-загрузчик для гибрида ------------------------------------------------
if ! detect_isohdpfx; then
  die "Не найден isohdpfx.bin. Установите:  sudo apt install isolinux   (или syslinux-common)."
fi
[ -f "$ISOHDPFX" ] && [ -r "$ISOHDPFX" ] || die "isohdpfx.bin недоступен: $ISOHDPFX"

# --- Определение файлов загрузки -----------------------------------------------
BIOS_OPTS=()
if [ -f "$ISO_DIR/isolinux/isolinux.bin" ]; then
  BIOS_OPTS=(-b isolinux/isolinux.bin -c isolinux/boot.cat -boot-load-size 4 -boot-info-table -no-emul-boot)
  c_info "BIOS-загрузка: isolinux"
elif [ -f "$ISO_DIR/boot/grub/i386-pc/eltorito.img" ]; then
  BIOS_OPTS=(-b boot/grub/i386-pc/eltorito.img -c boot/grub/boot.cat -boot-load-size 4 -no-emul-boot)
  c_info "BIOS-загрузка: GRUB (eltorito.img)"
else
  c_warn "Не найден BIOS-загрузчик (isolinux.bin / eltorito.img) - образ может не грузиться на legacy BIOS."
fi

EFI_OPTS=()
if [ -f "$ISO_DIR/efi.img" ]; then
  EFI_OPTS=(-eltorito-alt-boot -e efi.img -no-emul-boot)
  c_info "UEFI-загрузка: efi.img"
elif [ -f "$ISO_DIR/boot/grub/efi.img" ]; then
  EFI_OPTS=(-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot)
  c_info "UEFI-загрузка: boot/grub/efi.img"
else
  c_warn "Не найден EFI-образ (efi.img) - UEFI-загрузка может не работать."
fi

# --- Чистим образ перед упаковкой -----------------------------------------------
rm -f "$ISO_DIR/md5sum.txt"
# boot-каталоги xorriso пересоздаст сам
find "$ISO_DIR" -type f -name 'boot.cat' -delete 2>/dev/null || true

# Проверка метки тома
[ "${#ISO_VOLID}" -le 32 ] || c_warn "ISO_VOLID длиннее 32 символов - будет обрезано."

# --- Контрольная сумма (внутри образа) --------------------------------------------
c_info "Пересчитываем md5sum.txt ..."
( cd "$ISO_DIR" && find . -type f -not -name 'md5sum.txt' -exec md5sum {} + > md5sum.txt )

# --- Сборка ISO ----------------------------------------------------------------------
c_info "Сборка ISO: $OUTPUT_ISO"
rm -f "$OUTPUT_ISO"
mkdir -p "$(dirname "$OUTPUT_ISO")"

xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -joliet-long \
  -volid "$ISO_VOLID" \
  -appid "$DISTRO_NAME-$DISTRO_VERSION ($ISO_PUBLISHER)" \
  -publisher "$ISO_PUBLISHER" \
  -cache-inodes \
  -isohybrid-mbr "$ISOHDPFX" \
  "${BIOS_OPTS[@]}" \
  "${EFI_OPTS[@]}" \
  -isohybrid-gpt-basdat \
  -o "$OUTPUT_ISO" "$ISO_DIR" \
  || die "Xorriso завершился с ошибкой."

printf '%s\n' "$ISO_VOLID" | wc -c | grep -q '^[0-9]\{1,2\}$' || c_warn "Проверьте длину ISO_VOLID."
ls -lh "$OUTPUT_ISO"

# --- Контроль: squashfs внутри готового образа обязан читаться -------------------
# ВАЖНО: извлекаем в каталог ВНУТРИ WORKDIR (там гарантированно есть место,
# в отличие от /tmp, который может быть маленьким tmpfs). Целевое имя файла
# задаём явно (без '/'), чтобы xorriso не интерпретировал вывод двусмысленно.
c_info "Проверяем casper/filesystem.squashfs в собранном ISO..."
VERIFY_DIR=$(mktemp -d "$WORKDIR/.verify-mkiso.XXXXXX") 2>/dev/null || VERIFY_DIR=$(mktemp -d)
if xorriso -osirrox on -indev "$OUTPUT_ISO" \
     -extract /casper/filesystem.squashfs "$VERIFY_DIR/fs.squashfs" \
     >"$VERIFY_DIR/extract.log" 2>&1 \
   && unsquashfs -s "$VERIFY_DIR/fs.squashfs" >/dev/null 2>&1; then
  SRC_SIZE=$(stat -c%s "$SQUASH_FILE")
  DST_SIZE=$(stat -c%s "$VERIFY_DIR/fs.squashfs")
  if [ "$SRC_SIZE" = "$DST_SIZE" ]; then
    c_ok "squashfs в ISO читается (сверхблок корректен, размер совпадает: $DST_SIZE байт)."
  else
    c_warn "ВНИМАНИЕ: размер squashfs в ISO ($DST_SIZE) не совпадает с исходным ($SRC_SIZE)."
    c_warn "Образ может не загрузиться с 'No init found'. Проверьте стадии packages/roll."
  fi
else
  c_warn "ВНИМАНИЕ: squashfs в готовом ISO не извлечён или не читается."
  c_warn "Подробности (последние строки xorriso):"
  tail -n 5 "$VERIFY_DIR/extract.log" 2>/dev/null | sed 's/^/    /'
fi
rm -rf "$VERIFY_DIR"

c_ok "Стадия 06 завершена: собран $OUTPUT_ISO"