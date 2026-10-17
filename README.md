# ZoneZero Client (Godot 4)

Клиент MVP: гексагональная сетка 40×30 (cols×rows, offset), игроки — цветные круги.

## Запуск

1. Поднимите сервер (`../server/README.md`).
2. Откройте эту папку в **Godot 4.2+**.
3. Debug → Run Multiple Instances → **2**.
4. F5: ник → **Продолжить** → в комнате **Найти бой** (второе окно — другой ник).
5. Баланс (ОД/HP/хит/крит/оружие) приходит в `rules` уже с `lobby_state` — клиент не хардкодит коэффициенты. В бою: ход/выстрел по `rules` + оружию; наведение показывает %.
6. **Конец хода** или ждите 30 с — сервер резолвит и присылает новый стейт.

Адрес сервера задаётся в `scripts/net/server_config.gd`:

- `USE_PROD = false` → `ws://127.0.0.1:8080/ws` (локально)
- `USE_PROD = true` → `ws://103.167.235.247:8080/ws` (прод)

Протокол и запуск сервера — [server/README.md](../server/README.md). Архитектура — [server/docs/ARCHITECTURE.md](../server/docs/ARCHITECTURE.md). Характеристики — [server/docs/CHARACTER_STATS.md](../server/docs/CHARACTER_STATS.md).

Координаты 2D UI vs 3D карта (упор камеры к чату) — [docs/CAMERA_UI_COORDS.md](docs/CAMERA_UI_COORDS.md).
