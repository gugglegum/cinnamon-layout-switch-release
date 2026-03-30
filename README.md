# Cinnamon Layout Switch On Release

[![License: MIT](https://img.shields.io/github/license/gugglegum/cinnamon-layout-switch-release)](https://github.com/gugglegum/cinnamon-layout-switch-release/blob/master/LICENSE)
[![CI](https://github.com/gugglegum/cinnamon-layout-switch-release/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/gugglegum/cinnamon-layout-switch-release/actions/workflows/ci.yml)

Скрипты для Linux с окружением рабочего стола Cinnamon, которые позволяют переключать раскладку клавиатуры не в момент нажатия `Alt+Shift` или `Ctrl+Shift`, а в момент отпускания клавиш.

## Что это решает

В стандартной схеме переключения раскладки на Cinnamon/X11 комбинации вроде `Alt+Shift` обычно обрабатываются самим XKB. Это неудобно, если те же модификаторы участвуют в других горячих клавишах, например:

- `Alt+Shift+Tab`
- `Alt+Shift` + пользовательские хоткеи в IDE
- `Ctrl+Shift` + действия в терминале, редакторе или браузере

Проблема в том, что стандартный переключатель реагирует на нажатие комбинации, а не на её отпускание. В результате пользователь нажимает хоткей, а система успевает переключить раскладку раньше, чем хоткей завершён.

На Linux Mint 22.3 / Cinnamon 6.6.x всплывает и дополнительная проблема: если пытаться переключать раскладку внешними низкоуровневыми командами в обход самого Cinnamon, можно получить рассинхрон между реальным состоянием раскладки и апплетом в панели. В качестве примеров таких команд можно назвать прямое переключение XKB или смену IBus-движка из консоли. Внешне это выглядит так:

- фактический ввод уже идёт в одной раскладке, а флаг в панели показывает другую;
- переключение начинает срабатывать нестабильно;
- индикатор и реальная раскладка начинают жить отдельно.

Этот репозиторий решает именно эту комбинацию проблем.

## В чём суть решения

Решение состоит из двух частей.

### 1. CLI-переключатель `cinnamon-xkb-switch`

Это маленький Python-скрипт, который переключает раскладку не через прямое изменение XKB/IBus, а через D-Bus API самого Cinnamon:

- `org.Cinnamon.GetInputSources`
- `org.Cinnamon.ActivateInputSourceIndex`

То есть раскладка меняется тем же верхнеуровневым способом, которым её меняет сам Cinnamon. Благодаря этому:

- обновляется реальная раскладка;
- обновляется индикатор в панели;
- не возникает рассинхрон между Cinnamon и XKB.

### 2. Listener `kb-layout-switch-release.sh`

Это bash-скрипт, который слушает `xinput test`, отслеживает последовательности нажатия и отпускания модификаторов и только на отпускании вызывает `cinnamon-xkb-switch -n`.

Поддерживаются последовательности:

- `Alt+Shift`
- `Ctrl+Shift`

и в обоих порядках нажатия/отпускания.

Таким образом:

- хоткей с модификаторами может завершиться полностью;
- раскладка переключается только после отпускания;
- конфликт со многими `Alt+Shift+...` и `Ctrl+Shift+...` сочетаниями исчезает или резко уменьшается.

## Для каких систем это актуально

Точно протестировано на:

- Linux Mint 22.3 Zena
- Cinnamon 6.6.4
- X11

По смыслу решение должно быть актуально для любых дистрибутивов, где одновременно выполняются условия:

- используется Cinnamon;
- используется X11, а не Wayland;
- в сессионном D-Bus доступен интерфейс `org.Cinnamon` с методами `GetInputSources` и `ActivateInputSourceIndex`;
- переключение раскладки через штатный `Alt+Shift`/`Ctrl+Shift` конфликтует с другими хоткеями.

С высокой вероятностью это может быть полезно и для:

- LMDE с Cinnamon;
- Ubuntu Cinnamon;
- Fedora Cinnamon Spin;
- Arch Linux / Manjaro с Cinnamon.

Но это уже не прямой результат тестирования, а вывод из того, как устроен сам Cinnamon. На других дистрибутивах нужно просто проверить наличие того же D-Bus API и работу под X11.

## Когда это не поможет

Решение не рассчитано на:

- Wayland-сессии;
- GNOME Shell, KDE Plasma, Xfce, MATE и другие окружения без `org.Cinnamon`;
- системы, где раскладка переключается не через Cinnamon input sources;
- сценарии, где пользователь хочет использовать именно штатный XKB-переключатель без пользовательских скриптов.

## Содержимое репозитория

- `bin/cinnamon-xkb-switch` — CLI для чтения и переключения раскладки через D-Bus Cinnamon.
- `bin/kb-layout-switch-release.sh` — listener, который отслеживает `Alt+Shift` и `Ctrl+Shift` на отпускании.
- `autostart/kb-layout-switch-release.desktop.in` — шаблон автозапуска.
- `install.sh` — установка в `/usr/local/bin` и создание файла автозапуска в домашней директории пользователя.
- `uninstall.sh` — удаление установленных файлов.

## Требования

- Cinnamon
- X11
- `python3`
- `python3-gi`
- `xinput`
- `bash`
- `flock`
- доступ к пользовательской сессии D-Bus

На Linux Mint всё это обычно уже есть, кроме разве что нестандартных минимальных установок.

## Установка

Из корня репозитория:

```bash
chmod +x install.sh
./install.sh
```

Скрипт установит:

- `/usr/local/bin/cinnamon-xkb-switch`
- `/usr/local/bin/kb-layout-switch-release.sh`
- `~/.config/autostart/kb-layout-switch-release.desktop`

Если нужно указать другого пользователя для автозапуска:

```bash
TARGET_USER=paul ./install.sh
```

Если нужно установить не в `/usr/local/bin`, а в другой каталог:

```bash
INSTALL_BIN_DIR=/some/path ./install.sh
```

## Рекомендуемая настройка Cinnamon

Если вы хотите, чтобы раскладку переключал только этот listener, а не встроенные горячие клавиши Cinnamon, штатные сочетания лучше отключить:

```bash
gsettings set org.cinnamon.desktop.keybindings.wm switch-input-source "[]"
gsettings set org.cinnamon.desktop.keybindings.wm switch-input-source-backward "[]"
```

Также не стоит одновременно включать XKB-опции вроде `grp:alt_shift_toggle`, иначе получится двойное переключение: часть событий будет обрабатывать Cinnamon/XKB, часть — этот listener.

## Ручной запуск

Если не хочется перелогиниваться, listener можно запустить вручную:

```bash
/usr/local/bin/kb-layout-switch-release.sh
```

Для отладки:

```bash
KB_LAYOUT_SWITCH_DEBUG=1 /usr/local/bin/kb-layout-switch-release.sh
```

Можно явно указать конкретную клавиатуру:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_ID=8 /usr/local/bin/kb-layout-switch-release.sh
```

В тестовой виртуальной машине VMware во время отладки значение `KEYBOARD_ID=8` указывало на клавиатуру `AT Translated Set 2 keyboard`. Это удобный пример, но не универсальное правило: идентификаторы `xinput` зависят от конкретной системы, набора устройств и иногда могут меняться между загрузками.

В самой репозиторной версии скрипта `ID=8` не захардкожен. Скрипт сначала пытается найти клавиатуру по имени, а переменная `KB_LAYOUT_SWITCH_KEYBOARD_ID` нужна как ручное переопределение для нестандартных случаев или отладки.

### Как определить свой идентификатор клавиатуры

Сначала выведите список устройств:

```bash
xinput list --short
```

Обычно вы увидите что-то вроде:

```text
AT Translated Set 2 keyboard    id=8
```

или другое имя клавиатуры и другой `id`.

Если нужное имя уже известно, можно получить только его идентификатор:

```bash
xinput list --id-only "AT Translated Set 2 keyboard"
```

Если хочется слушать не конкретную физическую клавиатуру, а мастер-клавиатуру X11 целиком, можно посмотреть и её:

```bash
xinput list --id-only "Virtual core keyboard"
```

После этого найденный `id` можно передать так:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_ID=<ваш_id> /usr/local/bin/kb-layout-switch-release.sh
```

или имя устройства:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_NAME="AT Translated Set 2 keyboard" /usr/local/bin/kb-layout-switch-release.sh
```

## Использование `cinnamon-xkb-switch`

Примеры:

```bash
cinnamon-xkb-switch
cinnamon-xkb-switch -l
cinnamon-xkb-switch -n
cinnamon-xkb-switch --prev
cinnamon-xkb-switch -s us
cinnamon-xkb-switch -s ru
cinnamon-xkb-switch -s 0
```

## Почему используется не прямое переключение XKB, а D-Bus Cinnamon

Потому что на современных версиях Cinnamon прямое переключение XKB в обход Cinnamon может привести к рассинхрону:

- XKB уже переключился;
- Cinnamon всё ещё считает активной старую раскладку;
- флаг в панели и реальный ввод не совпадают.

Переключение через `org.Cinnamon.ActivateInputSourceIndex` этого не ломает, потому что состояние меняется там, где Cinnamon сам ожидает его менять.

## Известные особенности

- У некоторых версий Cinnamon при смене раскладки флаг в панели может на долю секунды исчезать и появляться заново. Это выглядит как визуальное мигание апплета. По наблюдениям, это связано с самим keyboard applet Cinnamon, а не с данным listener.
- Скрипт рассчитан на переключение по двум модификаторам. Если нужна более сложная логика, её можно расширить в `kb-layout-switch-release.sh`.
- Listener использует `xinput test`, поэтому должен работать внутри X11-сессии пользователя.

## Удаление

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Лицензия

Проект распространяется по лицензии MIT. Это означает, что код можно свободно использовать, изменять, публиковать, встраивать в другие проекты и распространять дальше, включая коммерческое использование.
