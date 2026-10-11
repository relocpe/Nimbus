# Nimbus

Меню-бар приложение для macOS, которое обходит DPI-блокировки Discord и YouTube. Один клик по иконке в строке меню: включить, выбрать стратегию, подобрать лучшую автоматически.

macOS 14+, universal (Apple Silicon и Intel). English version below.

Nimbus сделан **на основе** [Flowseal/zapret-mac-discord-youtube](https://github.com/Flowseal/zapret-mac-discord-youtube). Движок: [bol-van/zapret](https://github.com/bol-van/zapret) (`nfqws` через `utun` и BPF). Рабочий пайплайн сохранён, переделан интерфейс.

## Интерфейс

Приложение живёт в строке меню (иконка-облако) и открывает всплывающее окно. В нём несколько экранов:

- **Главный экран.** Статус сервиса (включён, выключен, запуск, остановка, подбор), доступность Discord и YouTube (проверяется живыми запросами), текущая стратегия с коротким описанием, список стратегий, кнопка **Включить / Выключить**. В меню-шестерёнке: проверка и установка обновлений, выход.
- **Списки сайтов.** Свои домены и исключения: можно добавлять и удалять домены прямо в окне. Домен проверяется (без пробелов, корректное имя), дубли не добавляются. Если сервис запущен, он перезапускается и применяет список.
- **Подбор стратегии.** Тест перебирает установленные стратегии, показывает прогресс и оценку каждой («Качество: N»), затем предлагает лучшую. Её можно применить кнопкой, остановить тест или подобрать заново.
- **Обновления.** Приложение проверяет [релизы этого репозитория](https://github.com/samevamp/Nimbus/releases) и ставит новую версию (проверяется контрольная сумма и архитектура архива).

## Возможности

- Стратегии из сборки Flowseal (в том числе `general-alt11`, `general-fake-tls-auto*`, `general-simple-fake*`); GameFilter вырезан.
- Режимы IPSet в движке: `none` (по умолчанию), `loaded` (список `ipset-all.txt`), `any` (все IPv4 за вычетом исключений). Режим хранится в `~/Library/Application Support/ZapretMac/ipset-mode`.
- Пользовательские списки доменов и исключений.
- Тест стратегий (`test-strategies.sh`) с отчётом.
- Автообновление из релизов GitHub.

Выход из приложения закрывает только окно в строке меню; сервис работает, пока вы не нажмёте **Выключить**.

> Скриншоты интерфейса будут добавлены отдельным коммитом.

## Установка

1. Выключите VPN с туннелированием.
2. Поставьте DNS не от провайдера: Google (`8.8.8.8`) или Cloudflare (`1.1.1.1`), лучше DNS over HTTPS, например [профиль Google Public DNS](https://github.com/paulmillr/encrypted-dns).
3. Скачайте `Nimbus-macOS-universal.zip` из [Releases](https://github.com/samevamp/Nimbus/releases) и перенесите `Nimbus.app` в «Программы».
4. Откройте приложение. Если Gatekeeper ругается: ПКМ → **Открыть**, либо **Системные настройки → Конфиденциальность и безопасность → Подтвердить вход**.
5. Клик по облаку → стратегия → **Включить**.

## Списки

Файлы лежат в `~/Library/Application Support/ZapretMac/lists`:

- `list-general-user.txt`: свои домены (поддомены подхватываются сами);
- `list-exclude-user.txt`: исключения доменов;
- `ipset-exclude-user.txt`: исключения IP.

## Сборка

```bash
./macos/build.sh
```

Архив: `dist/Nimbus-macOS-universal.zip`. Если у вас новый SDK, на котором не находится плагин макросов SwiftUI, укажите другой: `MACOS_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ./macos/build.sh`.

GitHub Actions (`.github/workflows/macos.yml`) собирает universal-билд на каждый пуш, релиз собирает `release.yml` по тегу.

## Принудительная остановка

```bash
sudo "/Library/Application Support/ZapretMac/stop.sh"
```

## Дисклеймер

Проект предоставляется «как есть», для личного использования и не гарантирует обход блокировок. Пользуйтесь на свой риск и в соответствии с законодательством вашей страны.

## Лицензия

MIT. Copyright bol-van, Flowseal, Nimbus. Благодарности: [Flowseal](https://github.com/Flowseal/zapret-mac-discord-youtube) и [bol-van/zapret](https://github.com/bol-van/zapret).

---

## English

Nimbus is a native macOS (14+, universal) menu-bar app that bypasses DPI blocking of Discord and YouTube. It is based on [Flowseal/zapret-mac-discord-youtube](https://github.com/Flowseal/zapret-mac-discord-youtube) and the [bol-van/zapret](https://github.com/bol-van/zapret) engine.

- Popover UI from the menu bar: service status, live Discord/YouTube reachability, strategy list, one-button on/off.
- Custom site lists and exclusions editable in the app.
- Strategy test that tries the bundled strategies, scores them and offers to apply the best one.
- IPSet modes in the engine: `none`, `loaded`, `any`.
- Self-updater using this repository's GitHub releases.

Install: download `Nimbus-macOS-universal.zip` from Releases, move `Nimbus.app` to Applications, open it (right-click → Open if Gatekeeper complains). Build: `./macos/build.sh`. Provided as-is, use at your own risk. MIT license; credits to bol-van and Flowseal.
