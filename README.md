# Mint ISO Build — сборщик дистрибутива на базе Linux Mint

Набор bash-скриптов для сборки собственного установочного дистрибутива
(Live+Install ISO) на пакетной базе Linux Mint. Позволяет:

- **изменять состав пакетов** базовой сборки (удалять лишнее, доустанавливать нужное из официальных репозиториев);
- **устанавливать программы из `.deb`-пакетов** внутрь образа — до сборки ISO;
- **полностью брендировать** дистрибутив (имя, метаданные, загрузочные меню, обои, plymouth, логотипы), включая внутренние инструменты Mint (About, mintreport, Welcome);
- **защищаться от «битых» сборок** — автоматические проверки не дают упаковать в ISO пустую/неполную live-ФС (ошибка `No init found`);
- получать готовый **гибридный образ (BIOS+UEFI)**, пригодный для записи на флешку через `dd`.

---

## Структура

```
mint-src/
├── build.sh                   # управляющий скрипт (запуск стадий)
├── config/
│   ├── build.conf             # ⚙ ВСЯ настройка сборки
│   ├── packages-remove.list   # пакеты для УДАЛЕНИЯ из базовой сборки
│   ├── packages-add.list      # пакеты для ДОустановки из репозиториев
│   ├── deb/                   # сюда кладёте .deb — ставятся до сборки ISO
│   └── ...                    # (в этот каталог собирается готовый образ)
├── output/                    # 📦 готовые ISO-образы (результат сборки)
│   └── logs/                  # 📄 протоколы всех сборок (build-<дата>-<время>.log)
├── lib/
│   └── common.sh              # общие функции (лог, chroot, разбор списков)
├── scripts/
│   ├── 01-prepare.sh          # проверка окружения и исходного ISO
│   ├── 02-extract.sh          # извлечение ISO-образа
│   ├── 03-modify-squashfs.sh  # удаление/добавление пакетов, установка .deb
│   ├── 04-branding.sh         # брендирование
│   ├── 05-roll-squashfs.sh    # упаковка ФС обратно в squashfs
│   ├── 06-mkiso.sh            # сборка итогового гибридного ISO
│   ├── 07-cleanup.sh          # очистка рабочих каталогов
│   └── 08-prune.sh            # удаление старых ISO-сборок (ротация)
└── brand/                     # материалы бренда (оверлеи)
    ├── root/                  #   -> внутрь live-ФС внутри squashfs
    ├── iso/                   #   -> в корень ISO
    └── boot/                  #   -> полная замена grub.cfg / isolinux.cfg
```

---

## Требования

- Дистрибутив **Linux Mint / Ubuntu / Debian** (хост сборки), архитектура **amd64**.
- Права **root** (`sudo`).
- Установленные пакеты: `xorriso`, `squashfs-tools`, `isolinux` (или `syslinux-common`).
  ```
  sudo apt install xorriso squashfs-tools isolinux
  ```
- **Интернет** на стадии `packages` (нужны репозитории Mint/Ubuntu для `apt`).
- Свободное место на диске — **не менее 2–3 размеров базового ISO** (рекомендуется от 12 ГБ).

---

## Быстрый старт

1. **Задайте конфигурацию** — откройте `config/build.conf` и укажите главное:

   - `SOURCE_ISO` — путь к ISO-образу Linux Mint (например, `linuxmint-21.3-cinnamon-64bit.iso`);
   - `DISTRO_NAME`, `DISTRO_VERSION` — имя и версия вашего дистрибутива;
   - `OUTPUT_ISO` — куда сохранить итог (по умолчанию — в папке проекта `output/`).

2. **(Опционально) настройте состав пакетов:**

   - `config/packages-remove.list` — что убрать (игры, LibreOffice и т.п.);
   - `config/packages-add.list` — что добавить (git, vim, …);
   - `config/deb/` — положите нужные `.deb`-файлы.

3. **(Опционально) подготовьте бренд:**

   - `brand/root/usr/share/backgrounds/…` — обои, plymouth-тема, логотипы;
   - `brand/iso/…` — картинки/шрифты grub на уровне ISO;
   - `brand/boot/grub.cfg`, `brand/boot/isolinux.cfg` — полные замены загрузочных меню.

   Подробности — в `brand/README`.

4. **Запустите сборку:**

   ```bash
   sudo ./build.sh            # все стадии подряд
   ```

   Или по стадиям:

   ```bash
   sudo ./build.sh check      # только проверка окружения
   sudo ./build.sh packages   # только изменение состава пакетов
   sudo ./build.sh mkiso      # только сборка ISO (после roll)
   ```

5. **Проверьте результат** и запишите на флешку:

   ```bash
   ls -lh output/*.iso
   sudo dd if=output/MyMint-1.0-amd64.iso of=/dev/sdX bs=4M status=progress
   ```

   Проверка в виртуальной машине (рекомендуется перед записью):

   ```bash
   qemu-system-x86_64 -m 4096 -cdrom output/MyMint-1.0-amd64.iso -boot d
   ```

---

## Стадии сборки

| Стадия | Скрипт | Что делает |
|---|---|---|
| `check` | `01-prepare.sh` | проверяет программы, свободное место, исходный ISO |
| `extract` | `02-extract.sh` | извлекает ISO через `xorriso` в `WORKDIR/iso` |
| `packages` | `03-modify-squashfs.sh` | распаковывает `filesystem.squashfs`, в chroot: удаляет пакеты, ставит пакеты из репо и `.deb` из `config/deb/` |
| `brand` | `04-branding.sh` | переименовывает «Linux Mint» → `DISTRO_NAME`: загрузочные меню, `os-release`/`lsb-release`/`linuxmint/info`, hosts/hostname, **`mintreport`**, **обои как фон по умолчанию**, оверлеи `brand/` |
| `prune` | `08-prune.sh` | **очистка от старых образов**: в `output/` остаётся `BUILD_KEEP` последних ISO, лишние удаляются (до сборки нового) |
| `roll` | `05-roll-squashfs.sh` | **защитный контроль rootfs** (не даёт упаковать пустую/неполную ФС), упаковывает ФС в `casper/filesystem.squashfs`, обновляет манифесты и `filesystem.size` |
| `mkiso` | `06-mkiso.sh` | собирает гибридный BIOS+UEFI ISO, пересчитывает `md5sum.txt`, **проверяет squashfs внутри готового ISO** |
| `clean` | `07-cleanup.sh` | размонтирует chroot, удаляет `WORKDIR` (если `KEEP_WORK=0`) |

Все стадии идемпотентны — можно запускать многократно и по отдельности.
При прерывании сборки (`Ctrl+C`) скрипт стадии `packages` сам размонтирует chroot.

Каждый запуск `build.sh` пишет полный протокол в `output/logs/build-<дата>-<время>.log` (все стадии, вывод apt/chroot, xorriso). Старые лог-файлы ротируются (хранятся последние 20).

---

## Изменение состава пакетов

- **Удаление.** Впишите имена в `config/packages-remove.list`. Удаляется пакет и всё, что от него зависит, поэтому указывайте верхнеуровневые (мета)пакеты, иначе останется много «осиротевших» библиотек. Проверить влияние:
  ```
  sudo ./build.sh packages
  ```
  или заранее симуляция: `apt-get -s remove [имя]`.

- **Добавление.** Имена в `config/packages-add.list` — установятся из официальных репозиториев Mint/Ubuntu.

- **Установка `.deb` до сборки ISO.** Положите файлы в `config/deb/` (архитектура **amd64**). Они ставятся через `dpkg -i` внутрь распакованной live-системы, зависимости дотягиваются автоматически (`apt-get -f`). Пакет попадает и в live-режим, и в установленную систему. Итоговые `.deb` в образ не попадают.

---

## Брендирование

Автоматически при стадии `brand`:

- «Linux Mint» → `DISTRO_NAME` во всех загрузочных конфигах ISO (`grub.cfg`, `isolinux.cfg`, `txt.cfg` …);
- **`os-release`** — правится не только `/etc/os-release`, но и реальный файл `/usr/lib/os-release`, на который он ссылается (в Mint это символьная ссылка). Патч идёт через `readlink`, чтобы не «перезаписать саму ссылку» новым файлом: имя, версия и все вхождения «Linux Mint» → `DISTRO_NAME`;
- **`lsb-release`** — `DISTRIB_ID` и `DISTRIB_DESCRIPTION` → `DISTRO_NAME` / `DISTRO_NAME DISTRO_VERSION`;
- **`/etc/linuxmint/info`** — `EDITION` → `DISTRO_NAME` (используется Welcome-экраном и некоторыми апплетами);
- **`mintreport`** — исходник `usr/lib/linuxmint/mintreport/app.py` патчится: имя дистрибутива в окне «Информация о системе» берётся из `DISTRO_NAME` вместо захардкоженного «Linux Mint» и выводится как `Alex Mint 64-bit` (без версии и издания);
- **`mintwelcome`** — окно «Добро пожаловать» (открывается первым в live-сессии) имеет собственный хардкод: `mintwelcome.py` тоже патчится (подпись значка ОС «Linux Mint 22.3» → «`Alex Mint` 22.3» и т.д.);
- `/etc/hostname` = `DEFAULT_HOSTNAME`;
- **обои как фон по умолчанию** — копирование jpg в `/usr/share/backgrounds` само по себе не меняет фон рабочего стола: Cinnamon берёт его из gsettings `org.cinnamon.desktop.background picture-uri`. Стадия:
  1. заменяет сам файл, на который указывает дефолтный `picture-uri` из gschema Cinnamon (в т.ч. ищет типовые `default_linuxmint*`);
  2. кладёт `gschema.override` (`zz_brand_background.gschema.override`) и пересобирает `gschemas.compiled` через `glib-compile-schemas`, если она есть на хосте;
  3. в качестве брендового фона берётся `brand/root/usr/share/backgrounds/default`, иначе — `wallpaper1.png`;
- обновление `.disk/info`;
- **контроль результата** — в лог выводится фактическое состояние `os-release`, `lsb-release`, `hostname`, список файлов обоев и `.disk/info`, чтобы сразу видеть, что брендирование применилось.

Через оверлеи:

| Каталог | Куда попадает |
|---|---|
| `brand/root/` | путь как в системе: `usr/share/backgrounds/fon.png` → `/usr/share/backgrounds/fon.png` внутри live-ФС |
| `brand/iso/` | корень ISO (splash grub, шрифты, readme) |
| `brand/boot/grub.cfg` / `isolinux.cfg` | полная замена загрузочного меню (⛔ только копируйте оригинал и правьте его — иначе образ не загрузится) |

Пример — сменить обои:

```
mkdir -p brand/root/usr/share/backgrounds
cp my-wallpaper.png brand/root/usr/share/backgrounds/
```

Чтобы брендовые обои стали **фоном по умолчанию** при загрузке, положите нужную картинку как `brand/root/usr/share/backgrounds/default`.

Плимут-тема загрузки (если она ставится в `/usr/share/plymouth/themes/mint-logo/…`) — кладётся аналогично в `brand/root/usr/share/plymouth/themes/…`.

---

## Защита сборки от ошибок

Стадии `roll` и `mkiso` содержат автоматические проверки, которые не дают получить «битый» ISO:

- **Контроль rootfs перед упаковкой** (`05-roll-squashfs.sh`). Перед `mksquashfs` проверяется, что распакованная live-ФС — настоящая полная система:
  - обязательно есть файлы `etc/os-release`, `usr/bin/bash`, `var/lib/dpkg/status`;
  - количество inode ≥ 50 000 и размер ≥ 1 ГБ.
  Если проверка не проходит — упаковка отменяется с ошибкой. Это защищает от ситуации, когда оверлей бренда «затирает» корень системы и в ISO попадает пустой squashfs (классическая причина ошибки загрузки **`No init found`**).
- **Проверка squashfs внутри готового ISO** (`06-mkiso.sh`). После сборки ISO стадия извлекает `casper/filesystem.squashfs` из готового образа **в каталог внутри `WORKDIR`** (не в `/tmp`, который может быть малым tmpfs), сверяет размер с исходным файлом и показывает подробности (`tail` лога xorriso) в случае сбоя. Такой контроль ловит проблему на этапе сборки, а не при загрузке с флешки.

---

## Основные переменные конфигурации

Все задаются в `config/build.conf` (со значениями по умолчанию) или переменной окружения.

| Переменная | Назначение | По умолчанию |
|---|---|---|
| `SOURCE_ISO` | путь к базовому ISO Linux Mint | — |
| `DISTRO_NAME` | имя дистрибутива (латиница) | `MyMint` |
| `DISTRO_VERSION` | версия | `1.0` |
| `ISO_VOLID` | метка тома ISO (≤ 32 симв.) | `MYMINT_1.0` |
| `ISO_PUBLISHER` | издатель (метаданные) | `MyOrg` |
| `DEFAULT_HOSTNAME` | hostname устанавливаемой системы | `mymint` |
| `WORKDIR` | рабочий каталог сборки (промежуточные файлы) | `/opt/mint-build/MyMint` |
| `OUTPUT_DIR` | каталог готовых образов | `output/` (в папке проекта) |
| `OUTPUT_ISO` | итоговый ISO | `output/…amd64.iso` |
| `PACKAGES_REMOVE_LIST` | список на удаление | `config/packages-remove.list` |
| `PACKAGES_ADD_LIST` | список на добавление | `config/packages-add.list` |
| `DEB_DIR` | каталог `.deb` | `config/deb` |
| `BRAND_DIR` | каталог материалов бренда | `brand/` |
| `BUILD_KEEP` | сколько последних ISO хранить в `output/` | `3` |
| `BUILD_LOG_DIR` | каталог логов сборки | `output/logs/` |
| `KEEP_WORK` | сохранять ли `WORKDIR` после сборки | `1` |

Пример переопределения из командной строки:

```bash
sudo SOURCE_ISO=/home/user/linuxmint.iso DISTRO_NAME=Corporate \
     DISTRO_VERSION=2026.1 ./build.sh
```

---

## Как это работает (кратко)

1. ISO Mint извлекается в каталог (`xorriso -osirrox on`).
2. `casper/filesystem.squashfs` распаковывается в каталог-«rootfs».
3. В него (через `chroot` с примонтированными `/dev /proc /sys /run`) вносятся изменения: `apt` удаляет/ставит пакеты, `dpkg` ставит `.deb`.
4. Применяется брендирование (оверлеи + правка конфигов).
5. Файловая система пакуется назад в `filesystem.squashfs`, пересчитываются манифесты и размер.
6. `xorriso` собирает гибридный ISO (BIOS: isolinux или grub `eltorito.img`; UEFI: `efi.img`) с MBR `isohdpfx.bin` и re-генерированным `md5sum.txt`.

Загрузочная компоновка исходного образа определяется автоматически (Linux Mint ≤ 21 — isolinux; новые Ubuntu/Mint — GRUB), поэтому скрипт работает с разными версиями Mint.

---

## Частые вопросы

**Q: Нужен ли интернет во время сборки?**
Только на стадии `packages` (для `apt-get update/install`). Если вы ничего не добавляете/не удаляете — можно обойтись без сети.

**Q: Можно ли менять версию через `packages-add.list`?**
Да — допустимы любые аргументы `apt-get install`, например `xserver-xorg=6:1.5.2-1`.

**Q: Что делать при ошибке «Не найден isohdpfx.bin»?**
Установите: `sudo apt install isolinux` (либо `syslinux-common`).

**Q: Образ не грузится на флешке.**
Запишите гибридный ISO через `dd` (битой) либо с помощью `Rufus` в режиме «DD-образ». Обычные «ISO copy» в Rufus/Win32DiskImager не подходят для гибридных образов.

**Q: Образ грузится с ошибкой `No init found`?**
Это значит, что в `filesystem.squashfs` упакована пустая/неполная live-ФС. Сборщик защищён от этого (контроль rootfs в стадии `roll` + проверка squashfs в `mkiso`), но если ошибка всё же вылезает: удалите `WORKDIR` и соберите заново — `sudo ./build.sh clean && sudo ./build.sh`. Причина кроется в стадиях `packages`/`brand` (обычно — «затёртый» корень оверлеем).

**Q: Почему в одном месте имя дистрибутива поменялось, а в другом нет?**
Разные инструменты Mint читают имя из разных источников: `neofetch` и терминал — из `/etc/os-release` (`PRETTY_NAME`), а, например, `mintreport` — из захардкоженного в `app.py` имени + `/etc/linuxmint/info`. Сборщик правит все эти места, включая сами исходники Mint. Если какой-то инструмент всё ещё показывает старое имя — он просто не покрыт брендированием; добавьте правку в `04-branding.sh`.

**Q: Файл `md5sum.txt` нужен зачем?**
Он используется инсталлятором и каспером для проверки целостности; скрипт пересчитывает его при каждой сборке.

---

## Лицензия / ответственность

Делайте резервные копии важных данных и проверяйте готовый образ в виртуальной машине перед записью на реальное железо. Скрипты дистрибутируются «как есть», базовый ISO — собственность проекта Linux Mint; итоговый продукт формирует пользователь.