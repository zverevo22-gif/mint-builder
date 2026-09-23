#!/usr/bin/env bash
# ============================================================================
#  Стадия 02 - извлечение ISO-образа Linux Mint в рабочий каталог
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

require_root
[ -f "$SOURCE_ISO" ] || die "Исходный ISO не найден: $SOURCE_ISO (см. config/build.conf)."

rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR"

c_info "Извлечение ISO: $SOURCE_ISO -> $ISO_DIR (может занять несколько минут)..."
xorriso -osirrox on -indev "$SOURCE_ISO" -extract / "$ISO_DIR" \
  || die "Не удалось извлечь ISO (xorriso)."

# Стабилизируем владельца
chown -R root:root "$ISO_DIR" 2>/dev/null || true

# Контрольные точки: содержимое обязано совпадать с типовой компоновкой Mint
[ -d "$ISO_DIR/casper" ]              || c_warn "В образе нет каталога casper/ (это не Linux Mint?)."
[ -f "$SQUASH_FILE" ]                 || die "В образе нет casper/filesystem.squashfs - сборка невозможна."
[ -f "$ISO_DIR/casper/vmlinuz" ]      || c_warn "Нет casper/vmlinuz - смотрите компоновку образа."
[ -f "$ISO_DIR/casper/initrd" ]       || [ -f "$ISO_DIR/casper/initrd.lz" ] || c_warn "Нет casper/initrd(.lz) - смотрите компоновку образа."

c_ok "Стадия 02 завершена. Образ извлечён в $ISO_DIR"