#!/usr/bin/env bash
# ============================================================================
#  Общая библиотека для всех стадий сборки.
#  Подключается в начале каждого скрипта стадии:  source .../lib/common.sh
# ============================================================================
set -euo pipefail

# --- Определение путей проекта ---------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$LIB_DIR")"
SCRIPTS_DIR="$ROOT_DIR/scripts"
CONFIG_DIR="$ROOT_DIR/config"

# --- Чтение конфигурации (переменные экспортируются дальше) ----------------
set -a
# shellcheck disable=SC1091
source "$CONFIG_DIR/build.conf"
set +a

# --- Вычисляемые пути сборки ------------------------------------------------
ISO_DIR="$WORKDIR/iso"        # извлечённый ISO-каталог
SQUASH_DIR="$WORKDIR/rootfs"  # распакованная live-ФС (для chroot)
SQUASH_FILE="$ISO_DIR/casper/filesystem.squashfs"

# --- Логирование ------------------------------------------------------------
c_info() { printf '\033[1;34m[СБОРКА]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[ГОТОВО]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[ВНИМАНИЕ]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# --- Общие проверки ---------------------------------------------------------
require_root() {
  [ "$(id -u)" -eq 0 ] || die "Требуются права root: запустите  sudo ./build.sh"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда '$1'. Установите:  sudo apt install $1"
}

# --- Работа с chroot --------------------------------------------------------
# Текущий каталог chroot; заполняется функцией mount_chroot
CHROOT=""

mount_chroot() {
  CHROOT="$1"
  c_info "Монтируем системные разделы в chroot: $CHROOT"
  for m in /dev /proc /sys /run; do
    mount --bind "$m" "${CHROOT}${m}" 2>/dev/null || true
  done
  # сеть для apt внутри chroot
  rm -f "$CHROOT/etc/resolv.conf"
  cp -f /etc/resolv.conf "$CHROOT/etc/resolv.conf" 2>/dev/null || true
}

umount_chroot() {
  local r="${1:-$CHROOT}"
  for m in /run /sys /proc /dev; do
    umount -l "${r}${m}" 2>/dev/null || true
  done
  sleep 1
}

# Выполнить команду внутри chroot с очищенным окружением
chroot_run() {
  [ -n "$CHROOT" ] || die "chroot не смонтирован (нужна стадия 03-пакеты)."
  chroot "$CHROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

# --- Чтение списков пакетов -------------------------------------------------
# Читает файл, отбрасывает комментарии ('#') и пустые строки,
# возвращает строку с пакетами, разделёнными пробелами.
read_list() {
  local f="$1" line out=()
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    line="${line%%#*}"                      # отрезать комментарий
    [ -n "${line// }" ] && out+=("$line")
  done < "$f"
  printf '%s' "${out[*]:-}"
}

# --- Поиск MBR-загрузчика для гибридного ISO ---------------------------------
ISOHDPFX=""
detect_isohdpfx() {
  ISOHDPFX=""
  for p in \
      /usr/lib/ISOLINUX/isohdpfx.bin \
      /usr/share/syslinux/isohdpfx.bin \
      /usr/lib/syslinux/isohdpfx.bin \
      "$ISO_DIR"/isolinux/isohdpfx.bin; do
    if [ -f "$p" ]; then ISOHDPFX="$p"; return 0; fi
  done
  return 1
}

# --- Определение сжатия исходного squashfs -----------------------------------
# Возвращает имя алгоритма (xz, zstd, ...) либо пустую строку.
detect_squashfs_compression() {
  unsquashfs -s "$SQUASH_FILE" 2>/dev/null \
    | sed -n 's/.*compression\s*\(\S*\)\s*$/\1/p' \
    | tr -d ' '
}