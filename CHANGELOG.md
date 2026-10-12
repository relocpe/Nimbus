# Changelog

Здесь только то, что менялось в Nimbus относительно
[Flowseal/zapret-mac-discord-youtube](https://github.com/Flowseal/zapret-mac-discord-youtube).
Изменения самого Flowseal смотрите в его репозитории.

## 2026-08-31 — Nimbus HUD

- Стандартное меню в строке меню заменено на панель HUD (`NimbusHUD.swift`).
- Автообновление теперь смотрит релизы этого репозитория.
- Приложение называется Nimbus, README переписан под него, в LICENSE добавлен Nimbus.
- В панели две точки состояния: доступны ли discord.com и youtube.com.
- Тест стратегий запускается из панели.
- Скрипты из `macos/Payload` сделаны исполняемыми, тест стратегий запускается через `/bin/sh`, чтобы работать из бандла приложения.
- Добавлены workflow для сборки universal-приложения на GitHub Actions и для релиза.

## 2026-09-06

- В `master` влит PR #2 (`nimbus-minibar`) с перечисленными выше изменениями.
