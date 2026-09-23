#!/usr/bin/env bash
# ============================================================================
#  Стадия 07 - очистка рабочих каталогов.
#  Размонтирует chroot (если стадия прервана) и удаляет WORKDIR,
#  если KEEP_WORK=0 в конфигурации.
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

require_root

# На всякий случай размонтируем остатки chroot
if [ -d "$SQUASH_DIR" ]; then
  umount_chroot "$SQUASH_DIR"
fi

# Размонтируем старые вложения ISO, если пользователь их оставлял
[ -d "$WORKDIR/mnt" ] && umount -l "$WORKDIR/mnt" 2>/dev/null || true

if [ "${KEEP_WORK:-1}" = "0" ] && [ -n "${WORKDIR:-}" ]; then
  c_info "Удаляем рабочий каталог $WORKDIR ..."
  rm -rf "$WORKDIR"
  c_ok "Рабочий каталог удалён."
else
  c_info "Рабочий каталог сохранён: $WORKDIR"
  c_info "Удалить вручную (после проверки результата):  rm -rf \"$WORKDIR\""
fi

c_ok "Стадия 07 завершена."