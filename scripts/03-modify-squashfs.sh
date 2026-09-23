#!/usr/bin/env bash
# ============================================================================
#  Стадия 03 - МОДИФИКАЦИЯ состава пакетов live-системы.
#
#  Распаковывает casper/filesystem.squashfs в chroot-каталог и внутри него:
#    * удаляет пакеты                        (config/packages-remove.list)
#    * ставит пакеты из официальных репо     (config/packages-add.list)
#    * ставит локальные .deb                   (config/deb/*.deb)
#  Требуется доступ в интернет (репозитории Mint/Ubuntu).
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

require_root
[ -f "$SQUASH_FILE" ] || die "Нет исходного squashfs: $SQUASH_FILE. Сначала выполните стадию 02."

# --- Распаковка live-ФС -----------------------------------------------------
rm -rf "$SQUASH_DIR"
mkdir -p "$SQUASH_DIR"
c_info "Распаковка filesystem.squashfs в $SQUASH_DIR..."
unsquashfs -d "$SQUASH_DIR" -no-progress "$SQUASH_FILE" >/dev/null 2>&1 \
  || die "Не удалось распаковать squashfs."

# --- Монтируем системные разделы в chroot -----------------------------------
mount_chroot "$SQUASH_DIR"
trap 'umount_chroot "$SQUASH_DIR"' EXIT INT TERM

c_info "apt-get update (репозитории Mint/Ubuntu)..."
chroot_run apt-get update -y || c_warn "apt-get update вернул ошибку, смотрим дальше."

# --- 1. Удаление пакетов -----------------------------------------------------
REMOVE=$(read_list "$PACKAGES_REMOVE_LIST")
if [ -n "$REMOVE" ]; then
  c_info "Удаляем из сборки: $REMOVE"
  chroot_run apt-get remove -y --purge $REMOVE || c_warn "Не все пакеты удалены (проверьте список)."
  chroot_run apt-get autoremove -y --purge || true
fi

# --- 2. Установка пакетов из репозиториев ------------------------------------
ADD=$(read_list "$PACKAGES_ADD_LIST")
if [ -n "$ADD" ]; then
  c_info "Устанавливаем из репозиториев: $ADD"
  chroot_run apt-get install -y $ADD || die "Ошибка установки пакетов из репозиториев."
fi

# --- 3. Установка программ из .deb ДО сборки ISO -----------------------------
if [ -d "$DEB_DIR" ] && compgen -G "$DEB_DIR"/*.deb >/dev/null 2>&1; then
  c_info "Устанавливаем .deb пакеты из $DEB_DIR ..."
  rm -rf "$SQUASH_DIR/tmp/deb-install"
  mkdir -p "$SQUASH_DIR/tmp/deb-install"
  cp -f "$DEB_DIR"/*.deb "$SQUASH_DIR/tmp/deb-install/"

  # Формируем список ПУТЕЙ ВНУТРИ chroot явно (не через шаблон '*', который
  # разворачивался бы на хосте, а не внутри chroot).
  deb_rel=()
  for _f in "$DEB_DIR"/*.deb; do
    deb_rel+=( "/tmp/deb-install/$(basename -- "$_f")" )
  done

  if ! chroot_run dpkg -i "${deb_rel[@]}"; then
    c_warn "dpkg -i не всё смог установить сразу - дотягиваем зависимости..."
    chroot_run apt-get install -f -y || c_warn "Не удалось дотянуть зависимости (см. вывод выше)."
    chroot_run dpkg --configure -a || true
  fi
  rm -rf "$SQUASH_DIR/tmp/deb-install"
  c_ok ".deb пакеты установлены."
fi

# --- Уборка внутри chroot ---------------------------------------------------
chroot_run apt-get clean || true
rm -f "$SQUASH_DIR/var/lib/apt/lists/lock" 2>/dev/null || true
# не оставляем хостовый resolv.conf в сборке (он будет поднят каспером при загрузке)
rm -f "$SQUASH_DIR/etc/resolv.conf" 2>/dev/null || true

umount_chroot "$SQUASH_DIR"
trap - EXIT INT TERM

c_ok "Стадия 03 завершена: состав пакетов live-системы изменён."