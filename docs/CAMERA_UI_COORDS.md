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

1. **Верх чата** — из `get_global_rect()` у `chat_dock` / `bottom_bar` (и окно, и fullscreen).
2. **В coords камеры** — `_ui_to_viewport()` = `get_viewport().get_canvas_transform().affine_inverse() * ui_pos`.
3. **Упор сдвига вниз** (`_clamp_focus`):
   - сдвиг камеры вниз → карта на экране едет вверх → растёт пустота над чатом;
   - луч через линию `верх_чата − CHAT_PAD_PX` (`_chat_strip_top_y`) → `z` на земле;
   - сравнить с югом коричневой земли (`_map_dirt_south_z`);
   - если луч южнее края карты — сдвинуть взгляд на север, пока пустота не станет ≤ отступа;
   - вверх и в стороны — **без** упоров;
   - зум **не** трогать (`ORTHO_SIZE_MIN = 22`).
4. **Земля** — плотно к полю (`grid_view._rebuild_ground_bed`, ~`ext * 2.02`): под чатом void, не коричневый пол под UI.

`CHAT_PAD_PX := 2.0` — зазор между низом карты и верхом чата.

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
