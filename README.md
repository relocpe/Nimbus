# Nimbus

Приложение для строки меню macOS, которое запускает zapret для обхода блокировок Discord и YouTube. Основано на [Flowseal/zapret-mac-discord-youtube](https://github.com/Flowseal/zapret-mac-discord-youtube), движок — [bol-van/zapret](https://github.com/bol-van/zapret).

## Требования

- macOS 14 или новее, Intel или Apple Silicon.
- Права администратора: при первом запуске устанавливается системный сервис.
- VPN должен быть выключен.
- DNS не от провайдера, например `1.1.1.1` или `8.8.8.8`.

## Установка

1. Скачайте `Nimbus-macOS-universal.zip` из [релизов](https://github.com/relocpe/Nimbus/releases).
2. Распакуйте архив и переместите `Nimbus.app` в папку «Программы».
3. Приложение подписано ad-hoc. При первом запуске откройте его через ПКМ → «Открыть» или снимите карантин:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Nimbus.app
   ```

4. Нажмите на значок в строке меню, выберите стратегию и нажмите «Запустить». macOS запросит пароль администратора.

## Настройка

Стратегия выбирается в меню приложения. Подобрать подходящую стратегию помогает «Ещё» → «Тест стратегий».

Пользовательские списки редактируются в разделе «Списки» приложения или вручную в `~/Library/Application Support/ZapretMac/lists/`:

| Файл | Назначение |
| --- | --- |
| `list-general-user.txt` | Дополнительные домены |
| `list-exclude-user.txt` | Исключённые домены |
| `ipset-exclude-user.txt` | Исключённые IP-адреса |

После изменения списков выберите стратегию заново, чтобы сервис перезапустился.

Автозапуск приложения включается в настройках.

## Как это работает

Приложение устанавливает LaunchDaemon `io.github.flowseal.zapretmac` и файлы сервиса в `/Library/Application Support/ZapretMac`. Сервис запускает движок `utunws` на интерфейсе `utun50` и через правила `pf` (якорь `com.apple/zapret-macos`) направляет в него трафик на порты HTTP/HTTPS, Discord и QUIC. Watchdog снимает правила `pf`, если движок останавливается или меняется сетевое подключение.

## Сборка

```bash
git clone https://github.com/relocpe/Nimbus.git
cd Nimbus
./macos/build.sh
```

Требуются `swiftc`, `clang` и `make`. Результат: `build/macos/Nimbus.app` и архив `dist/Nimbus-macOS-universal.zip`. Сборка подписывается ad-hoc.

## Решение проблем

Логи доступны в меню «Ещё» → «Логи», основной файл — `engine.log`.

- **Сервис не запускается.** Проверьте `engine.log`. Чаще всего причина во включённом VPN.
- **Индикатор красный при запущенном сервисе.** Выберите другую стратегию и проверьте, что используется DNS не от провайдера.
- **После сбоя сервиса пропал интернет.** Остановите сервис вручную:

  ```bash
  sudo "/Library/Application Support/ZapretMac/stop.sh"
  ```

Если проблема не решена, создайте issue и приложите логи, удалив из них имя пользователя.

## Лицензия

MIT. Copyright bol-van, Flowseal, Nimbus. Подробности в [LICENSE](LICENSE).
