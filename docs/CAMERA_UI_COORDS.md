# Координаты: 2D UI vs 3D карта + упор камеры к чату

## Две системы координат

Чат/панели — **2D Control** (`CanvasLayer`). Карта — **3D** (`Camera3D`).

Stretch: `canvas_items` + design **1280×720** (`aspect=ignore`).

| Источник | Пространство |
| --- | --- |
| `Control.get_global_rect()` | canvas UI |
| `Camera3D.unproject` / `project_ray_*` | viewport камеры |

Сравнивать напрямую нельзя — отступ «мимо» чата и дыра над чатом.

## Рабочий подход (проверено)

Файл: [`scripts/main.gd`](../scripts/main.gd).

1. **Верх чата** — из `get_global_rect()` у `chat_dock` / `plan_dock` (и окно, и fullscreen).
2. **В coords камеры** — `_ui_to_viewport()` = `get_viewport().get_canvas_transform().affine_inverse() * ui_pos`.
3. **Упоры сдвига** (`_clamp_focus`), зум не трогать (`ORTHO_SIZE_MIN = 22`):
   - **Вниз:** void низ карты ↔ чат ≤ `CHAT_PAD_PX` (2).
   - **Вверх:** void над верхом карты ≤ `TOP_VOID_MAX_PX` (50).
   - **Горизонталь:** если карта **уже** экрана — держать по центру (сдвиг влево/вправо запрещён, поля сами равные); если **шире** — void от края карты до края экрана ≤ `SIDE_VOID_MAX_PX` (100).
   - При сильном zoom-out, если карта не заполняет разрешённую полосу — допустим компромисс.
4. **Земля** — плотно к полю (`grid_view._rebuild_ground_bed`, ~`ext * 2.02`): под чатом / за краями void, не коричневый пол под UI.

Константы: `CHAT_PAD_PX := 2.0`, `TOP_VOID_MAX_PX := 50.0`, `SIDE_VOID_MAX_PX := 100.0`.

## Запрещено

```gdscript
# ПЛОХО — разные пространства
gap = chat.get_global_rect().position.y - camera.unproject_position(world).y
```

```gdscript
# ХОРОШО
var chat_y = _ui_to_viewport(Vector2(0, chat.get_global_rect().position.y)).y
var z_lim = _ground_at_screen(Vector2(mid_x, chat_y - CHAT_PAD_PX)).z
# сравнить z_lim с югом земли, поправить _focus
```

Не решать дыру автоподгоном зума и не раздувать dirt bed под весь экран.
