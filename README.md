# Nimbus

[![Build](https://github.com/samevamp/Nimbus/actions/workflows/macos.yml/badge.svg?branch=master)](https://github.com/samevamp/Nimbus/actions/workflows/macos.yml)

Меню-бар приложение для мака, которое включает обход DPI для Discord и YouTube одной кнопкой. Облачко в строке меню, кликнул, нажал «Запустить».

Это доработка [Flowseal/zapret-mac-discord-youtube](https://github.com/Flowseal/zapret-mac-discord-youtube): движок и стратегии оттуда, а оболочку (панель, тест стратегий, автообновление) я переделал под себя. Сам движок это [bol-van/zapret](https://github.com/bol-van/zapret).

Нужен macOS 14+, при запуске сервиса спросит пароль админа.

Что есть: запуск и остановка, две точки (доступны ли сейчас discord.com и youtube.com), выбор из 21 стратегии (по умолчанию `general-simple-fake`), тест стратегий в «Ещё», свои списки доменов, логи, автозапуск и автообновление из релизов. Выход из приложения сервис не останавливает, только кнопка «Остановить».

## Установка

1. Выключи VPN.
2. Поставь DNS не от провайдера, например 1.1.1.1 или 8.8.8.8.
3. Скачай `Nimbus-macOS-universal.zip` из [релизов](https://github.com/samevamp/Nimbus/releases).
4. Если macOS не даёт открыть: ПКМ → Открыть.
5. Клик по облаку, выбрать стратегию, «Запустить».

Свои домены добавляются в `~/Library/Application Support/ZapretMac/lists/list-general-user.txt`, исключения в `list-exclude-user.txt` рядом. После правки перевыбери стратегию, чтобы сервис перезапустился.

## Сборка

```bash
git clone https://github.com/samevamp/Nimbus.git && cd Nimbus
./macos/build.sh
```

Нужны `swiftc`, `clang` и `make`. Приложение будет в `build/macos/Nimbus.app`, архив в `dist/`. Подпись ad-hoc.

## Если не работает

- сервис не стартует: «Ещё» → «Логи», смотри `engine.log`. Чаще всего включён VPN.
- точка красная, хотя сервис запущен: попробуй другую стратегию, тест в «Ещё» покажет, какая заходит. И проверь, что DNS не провайдерский.
- пропал интернет после падения сервиса:
  ```bash
  sudo "/Library/Application Support/ZapretMac/stop.sh"
  ```

Не помогло, пиши в issue приложив логи, только сотри оттуда имя пользователя.

## Спасибо

Flowseal и bol-van, без них этого бы не было.

MIT, copyright bol-van, Flowseal, Nimbus (см. [LICENSE](LICENSE)).
