#!/usr/bin/env bash
# ============================================================================
#  Сборщик дистрибутива на базе Linux Mint.
#
#  Использование:
#    sudo ./build.sh                     # выполнить все стадии подряд
#    sudo ./build.sh packages            # выполнить только одну стадию
#    sudo ./build.sh clean               # очистить рабочий каталог
#
#  Доступные стадии:
#    check     - проверка окружения (программы, место, исходный ISO)
#    extract   - извлечение ISO-образа в WORKDIR
#    packages  - УДАЛЕНИЕ/ДОБАВЛЕНИЕ пакетов и установка .deb ВНУТРИ live-ФС
#    brand     - брендирование дистрибутива
#    prune     - удаление старых ISO-сборок (ротация output/, по BUILD_KEEP)
#    roll      - упаковка изменённой ФС обратно в squashfs
#    mkiso     - сборка итогового гибридного ISO
#    clean     - размонтирование и удаление рабочих каталогов
#
#  Полный протокол каждого запуска пишется в BUILD_LOG_DIR
#  (по умолчанию <проект>/output/logs/build-<дата>-<время>.log).
#
#  Основные настройки - в config/build.conf (или переменными окружения).
# ============================================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

STAGE="${1:-all}"
STAGES_DIR="$SCRIPTS_DIR"

# --- Лог-файл сборки ----------------------------------------------------------
BUILD_LOG_DIR="${BUILD_LOG_DIR:-$OUTPUT_DIR/logs}"
mkdir -p "$BUILD_LOG_DIR"
BUILD_LOG="$BUILD_LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$BUILD_LOG") 2>&1
c_info "Лог сборки: $BUILD_LOG"

declare -A STAGES=(
  [check]="$STAGES_DIR/01-prepare.sh"
  [extract]="$STAGES_DIR/02-extract.sh"
  [packages]="$STAGES_DIR/03-modify-squashfs.sh"
  [brand]="$STAGES_DIR/04-branding.sh"
  [prune]="$STAGES_DIR/08-prune.sh"
  [roll]="$STAGES_DIR/05-roll-squashfs.sh"
  [mkiso]="$STAGES_DIR/06-mkiso.sh"
  [clean]="$STAGES_DIR/07-cleanup.sh"
)
ORDER=(check extract packages brand prune roll mkiso)

run_stage() {
  local name="$1" script="$2"
  c_info "=== Стадия: $name ($script) ==="
  bash "$script"
  c_ok "=== Стадия '$name' выполнена ==="
}

case "$STAGE" in
  all)
    for k in "${ORDER[@]}"; do run_stage "$k" "${STAGES[$k]}"; done
    c_ok "Сборка завершена. Итоговый образ: $OUTPUT_ISO"
    c_info "Проверьте образ в QEMU/VirtualBox или запишите на флешку:"
    c_info "  sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress"
    ;;
  check|extract|packages|brand|prune|roll|mkiso)
    [ -n "${STAGES[$STAGE]:-}" ] || die "Неизвестная стадия: $STAGE"
    run_stage "$STAGE" "${STAGES[$STAGE]}"
    ;;
  clean)
    run_stage clean "${STAGES[clean]}"
    ;;
  *)
    die "Неизвестная стадия: '$STAGE'.

Доступны: all, check, extract, packages, brand, prune, roll, mkiso, clean"
    ;;
esac