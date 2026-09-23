#!/usr/bin/env bash
# ============================================================================
#  Стадия 04 - БРЕНДИРОВАНИЕ дистрибутива.
#
#  Автоматически:
#    * заменяет "Linux Mint" на DISTRO_NAME в загрузочных конфигах ISO
#      (grub.cfg, isolinux.cfg, txt.cfg и т.п.);
#    * правит /etc/os-release, /etc/lsb-release внутри live-системы;
#    * прописывает /etc/hostname = DEFAULT_HOSTNAME;
#    * обновляет .disk/info на корне ISO.
#  Плюс применяются оверлеи из каталога brand/ (см. brand/README):
#    brand/root/  -> внутрь live-ФС (squashfs)
#    brand/iso/   -> в корень ISO
#    brand/boot/grub.cfg / isolinux.cfg -> ПОЛНАЯ замена загрузочных меню
# ============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

# раскомментируйте следующую строку, если хотите сразу проверять путь к rootfs
# require_root   # не обязательно: права root не нужны

# --- 1. Имя дистрибутива в загрузочных конфигах ------------------------------
c_info "Переименовываем 'Linux Mint' -> '$DISTRO_NAME' в загрузочных конфигах ISO..."
find "$ISO_DIR" -maxdepth 3 -type f \
     \( -name '*.cfg' -o -name '*.conf' -o -name '*.txt' \) \
     -print0 2>/dev/null | while IFS= read -r -d '' f; do
       sed -i "s/Linux Mint/$DISTRO_NAME/g" "$f" 2>/dev/null || true
     done

# --- 2. Идентификация системы ВНУТРИ live-ФС ---------------------------------
if [ -d "$SQUASH_DIR/etc" ]; then
  c_info "Обновляем идентификацию системы внутри live-ФС..."

  # /etc/os-release (в Ubuntu/Mint это может быть символьная ссылка
  # на /usr/lib/os-release - правим РЕАЛЬНЫЙ файл через readlink, чтобы
  # не заменить саму ссылку на новый файл)
  for _rel in "$SQUASH_DIR/etc/os-release" "$SQUASH_DIR/usr/lib/os-release"; do
    [ -e "$_rel" ] || continue
    _real=$(readlink -f "$_rel")
    if [ -f "$_real" ] && [ -r "$_real" ]; then
      sed -i \
        -e "s/^NAME=.*/NAME=\"$DISTRO_NAME\"/" \
        -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"$DISTRO_NAME $DISTRO_VERSION\"/" \
        -e "s/Linux Mint/$DISTRO_NAME/g" \
        "$_real" 2>/dev/null || true
    fi
  done
  # сообщаем в лог, Что реально записалось (для диагностики)
  c_info "os-release после брендирования:"
  sed -n '/^NAME=/,/^PRETTY_NAME/p' "$SQUASH_DIR/etc/os-release" 2>/dev/null | sed 's/^/    /' || true

  # /etc/lsb-release
  if [ -f "$SQUASH_DIR/etc/lsb-release" ]; then
    sed -i \
      -e "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION=\"$DISTRO_NAME $DISTRO_VERSION\"/" \
      -e "s/^DISTRIB_ID=.*/DISTRIB_ID=$DISTRO_NAME/" \
      -e "s/Linux Mint/$DISTRO_NAME/g" \
      "$SQUASH_DIR/etc/lsb-release" 2>/dev/null || true
  fi

  # /etc/linuxmint/info (Welcome, некоторые апплеты)
  if [ -f "$SQUASH_DIR/etc/linuxmint/info" ]; then
    sed -i -e "s/^EDITION=.*/EDITION=\"$DISTRO_NAME\"/" \
           -e "s/Linux Mint/$DISTRO_NAME/g" \
           "$SQUASH_DIR/etc/linuxmint/info" 2>/dev/null || true
  fi

  # mintreport строит строку ОС НЕ из os-release, а из захардкоженного
  # "Linux Mint" + /etc/linuxmint/info (RELEASE/EDITION). Правим исходник.
  _mr="$SQUASH_DIR/usr/lib/linuxmint/mintreport/app.py"
  if [ -f "$_mr" ]; then
    # сбрасываем возможный .pyc-кэш, иначе python может взять старый код
    rm -rf "$SQUASH_DIR/usr/lib/linuxmint/mintreport/__pycache__" 2>/dev/null || true
    sed -i -e "s/distribution = \"Linux Mint\"/distribution = \"$DISTRO_NAME\"/" \
           -e 's/f"{distribution} {release} - {edition} {architecture}"/f"{distribution} {architecture}"/' \
           "$_mr" 2>/dev/null || true
    if grep -q 'distribution = "'"$DISTRO_NAME"'"' "$_mr" 2>/dev/null && \
       grep -q 'f"{distribution} {architecture}"' "$_mr" 2>/dev/null; then
      c_ok "mintreport: имя ОС заменено на '$DISTRO_NAME'."
    else
      c_warn "mintreport: шаблон app.py не совпал - имя не изменено. Загляните в $SQUASH_DIR/usr/lib/linuxmint/mintreport/app.py"
    fi
  else
    c_warn "mintreport/app.py не найден - пропущено."
  fi

  # mintwelcome (окно "Добро пожаловать", открывается в live-сессии первым)
  # имеет собственный хардкод dist_name + RELEASE/EDITION из linuxmint/info.
  _mw="$SQUASH_DIR/usr/lib/linuxmint/mintwelcome/mintwelcome.py"
  if [ -f "$_mw" ]; then
    rm -rf "$SQUASH_DIR/usr/lib/linuxmint/mintwelcome/__pycache__" 2>/dev/null || true
    sed -i "s/dist_name = \"Linux Mint\"/dist_name = \"$DISTRO_NAME\"/" "$_mw" 2>/dev/null || true
    if grep -q 'dist_name = "'"$DISTRO_NAME"'"' "$_mw" 2>/dev/null; then
      c_ok "mintwelcome: имя ОС заменено на '$DISTRO_NAME'."
    else
      c_warn "mintwelcome: шаблон mintwelcome.py не совпал - имя не изменено."
    fi
  else
    c_warn "mintwelcome/mintwelcome.py не найден - пропущено."
  fi

  # /etc/hostname
  if [ -n "${DEFAULT_HOSTNAME:-}" ]; then
    printf '%s\n' "$DEFAULT_HOSTNAME" > "$SQUASH_DIR/etc/hostname"
  fi
else
  c_warn "Не найден каталог $SQUASH_DIR/etc - брендирование системы пропущено."
  c_warn "Выполните стадию 03 (пакеты), чтобы распаковать live-ФС."
fi

# --- 3. Оверлей бренда внутрь live-ФС -----------------------------------------
if [ -d "$BRAND_DIR/root" ] && [ -n "$(ls -A "$BRAND_DIR/root" 2>/dev/null)" ]; then
  c_info "Применяем оверлей brand/root -> live-ФС..."
  rsync -a --exclude='.gitkeep' "$BRAND_DIR/root"/ "$SQUASH_DIR"/
fi

# --- 3b. Брендовые обои КАК ФОН ПО УМОЛЧАНИЮ ------------------------------------
# Простое копирование jpg в /usr/share/backgrounds НЕ меняет фон рабочего стола:
# Cinnamon берёт его из gsettings org.cinnamon.desktop.background picture-uri,
# а дефолт этого ключа задан в gschema (или в live-профиле).
# Чтобы после загрузки сразу был наш фон:
#   1) правим gschema.override (для установленной системы и новых пользователей);
#   2) подменяем сам файл, на который указывает picture-uri по умолчанию
#      (для live-сессии, где настройки пользователя берутся из жёстко зашитого URI).
BRAND_DEFAULT_WALL=""
for _cand in "$BRAND_DIR/root/usr/share/backgrounds/default" \
             "$BRAND_DIR/root/usr/share/backgrounds/wallpaper1.png"; do
  if [ -f "$_cand" ]; then BRAND_DEFAULT_WALL="$_cand"; break; fi
done

if [ -n "$BRAND_DEFAULT_WALL" ]; then
  c_info "Настраиваем брендовые обои как фон по умолчанию: $(basename "$BRAND_DEFAULT_WALL") ..."

  # 2a. Определяем путь default picture-uri из gschema Cinnamon
  _gsc="$SQUASH_DIR/usr/share/glib-2.0/schemas/org.cinnamon.desktop.background.gschema.xml"
  _def_uri=""
  if [ -f "$_gsc" ]; then
    _def_uri=$(sed -n '/picture-uri/,+2p' "$_gsc" \
                | grep -o "file://[^'\"]*" | head -1)
  fi
  # при прямом пути типа file:///usr/share/backgrounds/... отрезаем "file://"
  _def_path="${_def_uri#file://}"

  # 2b. Если gschema не найден - ищем типовые дефолтные обои Mint
  if [ -z "$_def_path" ]; then
    _def_path=$(find "$SQUASH_DIR/usr/share/backgrounds/linuxmint" -maxdepth 1 \
                 -type f \( -name 'default_linuxmint*' -o -name 'default_*' \) \
                 2>/dev/null | head -1 | sed "s|^$SQUASH_DIR||")
  fi

  # 2c. Подменяем сам целевой файл (только если он реально существует)
  if [ -n "$_def_path" ] && [ -f "$SQUASH_DIR/$_def_path" ]; then
    cp -f "$BRAND_DEFAULT_WALL" "$SQUASH_DIR/$_def_path"
    c_ok "Файл фона по умолчанию заменён: $_def_path"
  else
    # fallback: как минимум кладём бренд под явным именем default
    cp -f "$BRAND_DEFAULT_WALL" "$SQUASH_DIR/usr/share/backgrounds/default"
    c_info "Явного дефолта не найдено, положен /usr/share/backgrounds/default"
  fi

  # 2d. gschema.override для установленной системы / новых пользователей
  _ov="$SQUASH_DIR/usr/share/glib-2.0/schemas/zz_brand_background.gschema.override"
  _uri_in_fs="/usr/share/backgrounds/$(basename "$BRAND_DEFAULT_WALL")"
  printf '[org.cinnamon.desktop.background]\npicture-uri = '"'"'file://%s'"'"'\n' "$_uri_in_fs" > "$_ov"

  # 2e. Пересборка gschemas.compiled в rootfs (если glib-compile-schemas доступен)
  if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "$SQUASH_DIR/usr/share/glib-2.0/schemas" \
      >/dev/null 2>&1 && c_ok "gschemas пересобраны (фон по умолчанию = бренд)." \
      || c_warn "Не удалось пересобрать gschemas.compiled (может не сработать в live)."
  else
    c_warn "glib-compile-schemas не найден - gschema.override не применится."
  fi
else
  c_warn "Не найден брендовый фон для дефолта (brand/root/usr/share/backgrounds/default)."
fi

# --- 4. Оверлей бренда в корень ISO --------------------------------------------
if [ -d "$BRAND_DIR/iso" ] && [ -n "$(ls -A "$BRAND_DIR/iso" 2>/dev/null)" ]; then
  c_info "Применяем оверлей brand/iso -> корень ISO..."
  rsync -a "$BRAND_DIR/iso"/ "$ISO_DIR"/
fi

# --- 5. Полная замена загрузочных меню (опционально) ----------------------------
if [ -f "$BRAND_DIR/boot/grub.cfg" ]; then
  c_info "Заменяем boot/grub/grub.cfg на свой..."
  cp -f "$BRAND_DIR/boot/grub.cfg" "$ISO_DIR/boot/grub/grub.cfg"
fi
if [ -f "$BRAND_DIR/boot/isolinux.cfg" ]; then
  c_info "Заменяем isolinux/isolinux.cfg на свой..."
  cp -f "$BRAND_DIR/boot/isolinux.cfg" "$ISO_DIR/isolinux/isolinux.cfg"
fi

# --- 6. .disk/info --------------------------------------------------------------
if [ -d "$ISO_DIR/.disk" ]; then
  printf '%s %s\n' "$DISTRO_NAME" "$DISTRO_VERSION" > "$ISO_DIR/.disk/info"
fi

# --- 7. Контроль результата ------------------------------------------------------
c_info "Контроль брендирования:"
{
  echo "  os-release:   $(grep -H '^NAME=' "$SQUASH_DIR/etc/os-release" 2>/dev/null | tr -s ' ')"
  echo "  lsb-release:  $(grep -H '^DISTRIB_DESCRIPTION=' "$SQUASH_DIR/etc/lsb-release" 2>/dev/null | tr -s ' ')"
  echo "  hostname:     $(cat "$SQUASH_DIR/etc/hostname" 2>/dev/null)"
  echo "  mintreport:   $(grep -c 'distribution = \"'$DISTRO_NAME'\"' "$SQUASH_DIR/usr/lib/linuxmint/mintreport/app.py" 2>/dev/null || true) патчей"
  echo "  mintwelcome:  $(grep -c 'dist_name = \"'$DISTRO_NAME'\"' "$SQUASH_DIR/usr/lib/linuxmint/mintwelcome/mintwelcome.py" 2>/dev/null || true) патчей"
  echo "  backgrounds:  $(ls "$SQUASH_DIR/usr/share/backgrounds" 2>/dev/null | grep -v '^linuxmint$' | tr '\n' ' ')"
  echo "  .disk/info:   $(cat "$ISO_DIR/.disk/info" 2>/dev/null)"
} | while IFS= read -r line; do c_info "$line"; done

c_ok "Стадия 04 завершена: брендирование применено."