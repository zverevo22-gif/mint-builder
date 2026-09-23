#!/usr/bin/env bash
# ============================================================================
#  Стадия 08 - ПРИБОРКА старых сборок (ротация готовых ISO).
#
#  В каталоге OUTPUT_DIR оставляет BUILD_KEEP последних образу
#  (по дате изменения) и удаляет более старые. Так output/ не забивается
#  десятками промежуточных образов. Ведёт запись об удалении в лог.
#  Выполняется автоматически перед стадией mkiso (см. build.sh).
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

# --- Ротация ISO-образов ------------------------------------------------------
if [ ! -d "$OUTPUT_DIR" ]; then
  c_info "Каталог готовых образов ещё не существует: $OUTPUT_DIR (создастся при сборке)."
  exit 0
fi

# Список ISO по убыванию даты модификации (сначала свежие)
mapfile -t isos < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.iso' \
                      -printf '%T@|%p\n' 2>/dev/null | sort -rn | cut -d'|' -f2-)

if [ "${#isos[@]}" -eq 0 ]; then
  c_info "Готовых ISO-образов нет - убирать нечего."
else
  c_info "Найдено образов: ${#isos[@]}, лимит BUILD_KEEP=$BUILD_KEEP"
  keep=0; removed=0
  for f in "${isos[@]}"; do
    keep=$((keep+1))
    if [ "$keep" -le "$BUILD_KEEP" ]; then
      c_info "   [KEEP ] $f"
    else
      c_info "   [ДОЛОЙ] $f"
      rm -f "$f" && removed=$((removed+1)) && c_ok "      -> удалён"
    fi
  done
  c_ok "Осталось свежих: ${keep}, удалено старых: ${removed}."
fi

# --- Ротация логов (держим последние 20 файлов протокола) ----------------------
if [ -d "$BUILD_LOG_DIR" ]; then
  mapfile -t logs < <(find "$BUILD_LOG_DIR" -maxdepth 1 -type f -name '*.log' \
                        -printf '%T@|%p\n' 2>/dev/null | sort -rn | cut -d'|' -f2-)
  lk=0
  for l in "${logs[@]:-}"; do
    lk=$((lk+1))
    if [ "$lk" -gt 20 ]; then
      rm -f "$l" 2>/dev/null || true
    fi
  done
  c_info "Логов в архиве: $lk (лимит: 20 файлов)."
fi

c_ok "Стадия 08 завершена."