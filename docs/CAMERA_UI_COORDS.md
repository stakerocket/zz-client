# Координаты: 2D UI vs 2D карта + упор камеры к HUD

## Две системы координат

Боевой HUD / панели — **2D Control** (`CanvasLayer`). Карта — **Node2D** под `Camera2D`.

Stretch: `canvas_items` + design **1280×720** (`aspect=ignore`).

| Источник | Пространство |
| --- | --- |
| `Control.get_global_rect()` | canvas UI |
| `Node2D` / `Camera2D` world | world (после camera transform → viewport) |

Сравнивать canvas-прямоугольник HUD напрямую с world-позицией гекса нельзя без перевода.

## Рабочий подход (проверено)

Файл: [`scripts/main.gd`](../scripts/main.gd).

1. **Верх боевого HUD** — из `get_global_rect()` у `char_dock` (не `chat_dock`; чат в углу на framing не влияет).
2. **В coords viewport** — `_ui_to_viewport()` = `get_viewport().get_canvas_transform().affine_inverse() * ui_pos`.
3. **Упоры сдвига** (`_clamp_focus`), зум не трогать ради framing (`ZOOM_MAX = 1.35` closest):
   - **Вниз:** void низ карты ↔ CharDock ≤ `HUD_PAD_PX` (2).
   - **Вверх:** void над верхом карты ≤ `TOP_VOID_MAX_PX` (50).
   - **Горизонталь:** если карта **уже** экрана — держать по центру; если **шире** — void ≤ `SIDE_VOID_MAX_PX` (100).
   - При сильном zoom-out допустим компромисс.
4. Карта — procedural hex sprites (`ZZGridView` + `ZZPixelArt`), без 3D ground bed.

Константы: `HUD_PAD_PX := 2.0`, `TOP_VOID_MAX_PX := 50.0`, `SIDE_VOID_MAX_PX := 100.0`.

## Запрещено

Не решать дыру автоподгоном зума.
Не ровнять низ карты по `chat_dock` — только по `char_dock`.
Не возвращать `Camera3D` / `man.glb` / SubViewport-3D превью.
