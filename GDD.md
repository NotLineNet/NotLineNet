# GAME DESIGN DOCUMENT (GDD)
## Проект "NLN"

---
## ПРАВИЛА ОБНОВЛЕНИЯ

Когда редактируется док выставлять в истории документа новую строчку с актуальными данными.
Измененные структуры помечать, а рядом добавлять обновленные под текущую версию.
Всегда должна быть информация по предыдущей версии и обновленная по текущей. Старую (2 версии до) - удаляем.

---

## 1. ОПРЕДЕЛЕНИЕ ИГРЫ

**Жанр:** Пошаговая тактическая игра-roguelike с движением по процедурно-генерируемому графу тайлов.

**Суть:** Три игрока поочередно проходят лабиринт из 2D-сетки тайлов. Каждый ход игрок имеет 3 очка действий (ОД), которые расходуются на переходы между тайлами. Цель — выбраться из стартовых "зелёных" тайлов на "красный" финишный тайл, пройдя через случайный лабиринт.

---

## 2. СТРУКТУРА СЦЕН ПРОЕКТА

### Иерархия основной сцены (Main.tscn):
```
Main (Node3D) - главная сцена
├── GameManager (Node3D) - управление состоянием игры
├── LevelManager (Node3D) - генерация и управление уровнем
├── PlayerManager (Node3D) - визуальное управление персонажами
├── LevelRoot (Node3D) - контейнер для тайлов
├── PlayerRoot (Node3D) - контейнер для игроков
├── CameraRoot (Node3D) - система камеры
│   └── CameraPivot (Node3D) + Camera3D
└── UI (CanvasLayer)
	├── HUD(cheats) - нижняя панель управления
	├── PlayerUI (экземпляр PlayerUI.tscn) - панель активного игрока
	└── MainHUD
		└── Portraits - портреты игроков в центре
```

### Инстанцируемые сцены:
- **Player.tscn** - узел игрока (Sprite3D + SpotLight3D)
- **Tile.tscn** - узел тайла (MeshInstance3D + Area3D для клика + BaseRoom с визуалом стен)
- **PlayerUI.tscn** - панель очков действий и кнопка окончания хода
- **IntroCutScene.tscn** - вступительная кат-сцена

---

## 3. ПОТОК ВЫПОЛНЕНИЯ ИГРЫ (GAME FLOW)

### Этапы жизненного цикла игры:

```
ИНИЦИАЛИЗАЦИЯ
	↓
game_loaded_full() [GameManager]
	↓
start_intro() → IntroCutScene анимация
	↓
intro_finished() → Подготовка камеры
	↓
game_started() → Показ UI и камера следует за игроком
	↓
_start_first_day()
	├─ Рефилл ОД всем игрокам (3 ОД)
	├─ Активный игрок = players[0]
	└─ Камера фокусируется на активном игроке
	↓
ИГРОВОЙ ДЕНЬ (активен цикл ходов)
	├─ Игрок кликает на выход тайла
	│  ├─ Проверка: ОД > 0, активный, не движется
	│  ├─ Player.move_to_tile() 
	│  │  ├─ Анимация движения (0.2 сек)
	│  │  ├─ Анимация камеры с задержкой (0.05 сек отстав, 0.3 сек движ)
	│  │  ├─ Рефилл видимости тайла (show_tile)
	│  │  └─ Трата 1 ОД
	│  └─ emit: active_player_action_points_changed
	│
	└─ Повтор для каждого игрока
	↓
request_player_finish_turn() [GameManager]
	├─ Отправка события в TurnStateMachine о желании игрока закончить ход
	├─ FSM делает DecidePlayerTurn -> PrepareEndTurn / CanPlayerActAgain
	├─ Когда все игроки завершили ходы, FSM эмитит turns_completed → night cycle
	│
start_new_day()
	├─ currentGameDay += 1
	├─ Рефилл ОД
	├─ Активный = players[0]
	└─ FSM стартует для нового игрока...
```

---

## 4. РОЛЬ И ОТВЕТСТВЕННОСТЬ КАЖДОГО КОМПОНЕНТА

### GameManager (главный оркестратор)
**Файл:** `scripts/core/GameManager.gd`  
**Роль:** Управление состоянием игры, логика ходов, коммутатор сигналов

**Ключевые переменные:**
- `currentGameDay: int` — день игры (начало = 1)
- `players: Array[Player]` — список всех игроков
- `active_player: Player` — текущий игрок
- `_active_player_index: int` — индекс в массиве
- Флаги: `_is_switching_turn`, `_is_waiting_new_day`, `_intro_completed`, `_game_started`

**Главные методы:**
- `game_loaded_full()` → запуск intro
- `game_started()` → включение UI и цикла ходов
- `register_player(player)` → добавление игрока в список
- `request_player_finish_turn()` → триггер для TurnStateMachine при завершении хода
- `set_active_player(player)` → переключение активного (с отключением сигналов от предыдущего)
- `_focus_camera_on_player(player)` → вспомогательная анимация камеры для FSM

**Сигналы:**
- `active_player_changed(new_player)` → слушают UI, PlayerManager, Tile
- `active_player_action_points_changed(new_value)` → слушают UI
- `new_player_started_moving(new_player)` → слушают UI
- `gameplay_started` → слушают UI
 - `player_turn_finished(player)` → отдает ход TurnStateMachine после завершения
 - `battle_state_changed(active: bool)` → экран UI скрывает/показывает финишную кнопку хода
 - `player_ready_after_battle(player)` → используется для синхронизации `Tile` / `RoomUI` после победы из тайла

**v1.2:** GameManager теперь инстанцирует `BattleStateMachine` (см. раздел ниже), проксирует события интерфейса (`show_battle_ui`, `_dep_show_battle_ui` и т.д.) и хранит `battle_ctx` с текущим игроком / монстром / тайлом. `start_monster_battle()` подготавливает контекст (тип боя: "Внезапный" / "Обычный"), ставит `state = GameState.BATTLE`, отправляет `battle_state_changed(true)` и ожидает, пока `BattleStateMachine` завершит последовательность состояний. `handle_battle_player_choice()` мостит UI-выборы к стейт-машине и подменяет тайл, с которого запрошен `run` (вариант "убежать"), чтобы применить штраф.

**Важно:** `_finish_battle()` сбрасывает состояния (`battle_choice_tile`, `_battle_ctx`, `_battle_in_progress`), восстанавливает камеру / ввод и, если бой начался из тайла и игрок выжил, посылает `player_ready_after_battle`, чтобы соответствующий `Tile` мог сменить визуал.

**Критическая зависимость:** Работает через group-поиск "game_manager"

---

### BattleStateMachine (регулятор битв)
**Файл:** `scripts/battle/BattleStateMachine.gd`  
**Роль:** Унифицировать последовательность фаз боев, не встраивая логику монстров внутрь `GameManager`. Загружает шесть состояний (PrepareBattle, DiceCheck, PreparePlayerChoice, PlayerChoice, PrepareEndBattle, EndBattle) и ожидает события/вызовы через делегированные зависимости.

**Состояния:**
- **PrepareBattle:** выключает ввод, скрывает/показывает UI, запускает `show_battle_ui`, выбирает следующую фазу по типу боя.
- **DiceCheck:** скрывает UI, запускает `run_dice_game(player, monster)` через dependency и записывает выигранный бросок.
- **PreparePlayerChoice:** проигрывает камеру удара, проверяет смертельный урон, при победе переводит напрямую в `PrepareEndBattle`, иначе переводит в `PlayerChoice`.
- **PlayerChoice:** включает ввод и `PlayerUI`, показывает `RoomUI` в боевом режиме, ожидает событие `player_choice` (fight/run); при run вызывает `apply_run_penalty`.
- **PrepareEndBattle:** в зависимости от результатов вызывает `handle_monster_death` или `handle_player_death`, ждет `hide_battle_ui`.
- **EndBattle:** вызывает `finalize_battle` и закрывает бой.

**Зависимости (через `_deps`):** `show_battle_ui`, `hide_battle_ui`, `enter_battle_room_ui`, `exit_battle_room_ui`, `disable_player_input`, `enable_player_input`, `play_camera_hit`, `run_dice_game`, `apply_player_damage`, `apply_run_penalty`, `handle_monster_death`, `handle_player_death`, `finalize_battle`. Нехватка хотя бы одного callable приводит к отсутствию визуальной обратной связи и потенциально зависающему состоянию — см. раздел 11.

**Сигналы:** `state_changed(state_name: String, ctx: Dictionary)` для debug/log, `battle_finished(result_ctx: Dictionary)` чтобы GameManager знал, что все фазы закрыты.

**Дополнительно:** `BattleState` (`scripts/battle/BattleState.gd`) — базовый класс, который переопределяют конкретные состояния; каждый `enter`, `exit` и `handle_event` получают общий контекст.

---

### LevelManager (генератор уровня)
**Файл:** `scripts/core/LevelManager.gd`  
**Роль:** Процедурная генерация лабиринта, управление графом связей тайлов

**Алгоритм генерации (create_grid):**

1. **Создание кругов тайлов:**
   - Красный круг (радиус: 9) с центром в (0, 0) — стартовая точка
   - 3 зелёных круга (радиус: 5) на периметре красного — финиши
   - Тайлы создаются, если дистанция ≤ радиус + 0.5

2. **Конфигурация особых тайлов:**
   - Красный: 4 выхода (force_all=true)
   - Зелёные: 1 выход (выбирается в сторону красного через `_choose_green_exit_direction`)

3. **Создание связного графа (BFS):**
   ```
   create_connected_graph() →
   - Посещаем все тайлы от зелёных и красного
   - Для непосещённых без выходов: создаём минимальный выход
   ```

4. **Гарантия путей:**
   - `ensure_path_between()` → линейный поиск к красному для каждого зелёного
   - `create_path_between()` → A* выбор ближайшего соседя к цели

5. **Случайные выходы (add_random_exits):**
   - Вероятность: 1 выход (5%), 2 (20%), 3 (60%), 4 (15%)
   - 15% шанс добавить дополнительный выход на каждый тайл
   - **Важно:** Зелёные тайлы принудительно ограничиваются 1 выходом после этого

**Ключевые жёсткие значения:**
- `TILE_SIZE = 4` — расстояние между тайлами в World Units
- `circle_radius = 5` (export) — радиус красного круга
- `green_circle_radius = 5` (export) — радиус зелёных
- Вероятности выходов: 0.05, 0.20, 0.60, 0.15
- Дополнительный выход: 0.15 (15%)
- Направления: UP, DOWN, LEFT, RIGHT (Vector2i)

**Визуальный отладочный режим:**
- `build_path_debug_lines()` → отрисовка связей оранжевыми линиями
- Кнопка "Пути" в HUD переключает видимость

---

### Player (логика движения игрока)
**Файл:** `scripts/core/Player.gd`  
**Роль:** Поведение отдельного персонажа, обработка кликов на выходы

**Статус игрока:**
- `current_tile: Tile` — текущий тайл
- `previous_tile: Tile` — тайл, откуда пришел (для отката)
- `is_moving: bool` — заблокирован ввод во время анимации
- `is_active: bool` — это активный игрок
- `action_points: int` — ОД (мин 0, макс 3)

**Жёсткие значения:**
- `MOVE_DURATION = 0.2` — анимация хода (сек)
- `CAMERA_MOVE_DURATION = 0.3` — анимация камеры (сек)
- `CAMERA_DELAY = 0.05` — отстав камеры (сек)
- `MAX_ACTION_POINTS = 3`
- `MIN_ACTION_POINTS = 0`
- `PLAYER_SIZE = 1.0` — половина размера тайла

**Главные методы:**
- `initialize_on_tile(tile)` → размещение на зелёном тайле при старте дня
- `set_active(active)` → переключение активности
- `move_to_tile(target_tile)` → 
  - Проверка ОД, is_active, is_moving
  - Анимация движения + камеры
  - Вычитание 1 ОД
  - Сигнал `action_points_changed`
- `_on_exit_clicked(tile, dir)` → обработчик клика на выход
- `spend_action_point()` → -1 ОД
- `refill_action_points()` → полный рефилл до 3

**Блокировки ввода:**
- Если `is_moving` → нет кликов
- Если `not is_active` → нет кликов
- Если `action_points == 0` → нет кликов

**Важное предположение:** Player не может быть на двух тайлах одновременно; только `current_tile` актуален.

---

### Tile (логика одного тайла)
**Файл:** `scripts/core/Tile.gd`  
**Роль:** Интерфейс взаимодействия, визуальная обратная связь

**Данные:**
- `grid_pos: Vector2i` — позиция в сетке
- `exits: Array[Vector2i]` — массив направлений выходов (MAX 4)
- `exit_markers: Dictionary` — маркеры выходов по направлениям
- `base_room: Node3D` — визуальная модель комнаты

**Жёсткие значения:**
- `EXIT_MARKER_SIZE = (0.3, 0.3, 0.3)`
- `EXIT_OFFSET = 0.9` — расстояние маркера от центра тайла
- `HOVER_SCALE = 1.2`, `NORMAL_SCALE = 1.0` — масштаб при наведении
- `GATE_COLOR_ACTIVE = зелёный (0.2, 1, 0, 1)`
- `GATE_COLOR_INACTIVE = серый (0.5, 0.5, 0.5, 1)`

**Методы:**
- `redraw_exit_markers()` → пересоздание всех маркеров на основе `exits`
- `show_tile()` / `hide_tile()` → видимость BaseRoom
- `on_player_entered()` → маркеры становятся зелёными (активными)
- `on_player_exited()` → маркеры становятся серыми (неактивными)

**Сигналы:**
- `exit_clicked(tile, dir)` → клик на маркер выхода (слушает Player)
- `tile_clicked(tile)` → клик на сам тайл (не используется в коде)

**Интерактивность:**
- Маркеры можно кликать только если игрок на этом тайле, не движется и это активный игрок

---

### CameraDrag (система камеры)
**Файл:** `scripts/core/CameraDrag.gd`  
**Роль:** 3D-камера с зумом, перетаскиванием и слежением за активным игроком

**Архитектура:**
- `CameraRoot` (Node3D) — главный контейнер, позиция X-Z (горизонтально)
  - `CameraPivot` (Node3D) — наклон и высота (Y, Z вращение)
	- `Camera3D` — поле зрения

**Zoom presets (zoom_presets)**
- _v1.0:_ фиксированные три пресета (0 = близко, 1 = средне, 2 = далеко).
- _v1.1:_ динамический массив словарей, которые хранят `position` (только Y и Z применяются к `CameraPivot`), `rotation_x`, `fov` и опционально `drag_speed`. Текущий `zoom_level` теперь варьируется от 0 до 3:
  1. Уровень 0 (максимальное отдаление): `Vector3(0,8,0)`, `rotation_x = -30°`, `fov = 70`.
  2. Уровень 1: `Vector3(0,6,0)`, `rotation_x = -35°`, `fov = 60`.
  3. Уровень 2: `Vector3(0,4,0)`, `rotation_x = -40°`, `fov = 50`.
  4. Уровень 3 (максимальное приближение): `Vector3(0,2,0)`, `rotation_x = -45°`, `fov = 40`.
  `_initialize_presets()` создаёт такие пресеты по умолчанию, если массив пуст.

**Жёсткие значения:**
- `drag_speed` — _v1.0:_ 0.01. _v1.1:_ 0.05 базовая скорость скролла, `current_drag_speed` копирует `drag_speed` из активного пресета (если там указан отдельный), иначе берёт базовое значение.
- `zoom_speed = 5.0` — скорость интерполяции зума.
- `camera_center_speed = 3.0` — скорость плавного центрирования при пресете 0.
- `auto_center_on_start = true` — при старте в пресете 0 камера сразу центрируется на игроке.
- Эйзинг: EASE_IN_OUT + TRANS_CUBIC на всех переходах.

**Режимы:**
- `follow_enabled` — слежение за игроком (отключается на intro, выключает автоцентрирование).
- `input_enabled` — разрешает ввод (перетаскивание/зум).
- `zoom_level` — текущий пресет (0–3).
- `is_centering_on_tile` — true, пока камера интерполируется к `target_tile_position` при `zoom_level == 0`.

**Дополнительные API:**
- `set_follow_enabled(bool)` / `set_input_enabled(bool)` — управляют вводом во время intro.
- `apply_zoom_preset(level, interpolate)` — программно переключает уровень зума.
- `center_camera_on_tile(tile)` — плавно центрирует камеру (в режиме follow) на тайле активного игрока.
- `focus_on_tile(tile, delay, duration)` — создаёт Tween, двигающий `CameraRoot`.
- `apply_external_camera_state(root_position, pivot_transform, fov_value)` — применяется после IntroCutScene.
- `sync_targets_to_current()` и `get_camera_height()` — синхронизируют внутренние цели и возвращают текущую высоту камеры.

**Особенность пресета 0:**
- Правая кнопка мыши блокируется (камера "прилипает" к тайлу активного игрока).
- `center_camera_on_tile()` и `_center_camera_on_player_tile()` инициируют плавное перемещение `CameraRoot` до `target_tile_position`.

---

### PlayerManager (визуальное управление)
**Файл:** `scripts/core/PlayerManager.gd`  
**Роль:** Применение текстур, портретов персонажей, масштабирование активного портрета

**Данные из метаданных сцены:**
```gdscript
PlayersViewParams = [
  { CharName: "Сэр Курочкин Горшок", CharBodyName: "hero_body_1", CharIconName: "hero_icon_1" },
  { CharName: "Синьер Шапка Солнце", CharBodyName: "hero_body_2", CharIconName: "hero_icon_2" },
  { CharName: "Мисье Курю Ножи", CharBodyName: "hero_body_3", CharIconName: "hero_icon_3" }
]
```

**Жёсткие значения:**
- `IMAGE_DIR = "res://image/"` — папка текстур
- `PORTRAIT_CONTAINER_PATH = "/root/Main/UI/MainHUD/Portraits/HBoxContainer"`
- `PORTRAIT_SCALE_ACTIVE = 1.1`, `PORTRAIT_SCALE_IDLE = 1.0`
- `PORTRAIT_TWEEN_DURATION = 0.15`

**Методы:**
- `update_active_player_display(player)` → смена текстуры тела, обновление имени
- `_highlight_active_portrait()` → масштабирование портрета активного (1.1x)

---

### UI / PlayerUI (визуальные панели)
**Файл:** `scripts/ui/UI.gd`, `scripts/ui/PlayerUI.gd`

**HUD(cheats) — нижняя панель:**
- Кнопки: Перезагрузка, Пути (вкл/выкл), +ОД (отладочная), Начать
- День: текущий день игры
- Сигналы с GameManager синхронизируют состояние

**PlayerUI — панель активного игрока:**
- Панель с портретом (Avatar), именем, ОД (3 визуальных элемента)
- Кнопка "Закончить ход" (видна, только если ОД = 0)
- AnimationPlayer для появления/исчезновения

---

### IntroCutScene (вступление)
**Файл:** `scripts/ui/IntroCutScene.gd`

**Роль:** Вступительная кат-сцена с собственной камерой  
**Жизненный цикл:**
1. Запускается после загрузки уровня
2. Имеет собственную CameraRoot + CameraPivot + Camera3D
3. Проигрывает анимацию "intro_camera_out"
4. После завершения → emit `intro_animation_finished`
5. GameManager забирает состояние камеры и переводит камеру на main

---

## 5. МЕХАНИКИ ИГРЫ

### 5.1 Система ОД (Action Points)
- **Стартовое:** 3 ОД в начале дня
- **Трата:** 1 ОД за один переход между тайлами
- **Условие хода:** ОД > 0
- **После хода:** Переключение на следующего игрока
- **Рефилл:** При переходе на новый день

**Хардкод:** MIN_ACTION_POINTS=0, MAX_ACTION_POINTS=3

### 5.2 Система ходов
- **Последовательность:** Игрок 1 → Игрок 2 → Игрок 3 → новый день
- **Блокировка:** Во время анимации движения нельзя кликать
- **Задержка между ходами:** 2 сек (TURN_SWITCH_DELAY)
- **Кнопка "Закончить ход":** Нажимается, когда ОД=0, вызывает `request_player_finish_turn()`

### 5.3 Система визуальной обратной связи
- **Маркеры выходов:** 
  - Зелёные = активные (игрок на тайле)
  - Серые = неактивные
  - Масштабируются на наведении (1.0 → 1.2)
- **Смена цвета:** on_player_entered() / on_player_exited()
- **Видимость тайлов:**
  - Стартовые зелёные + красный = видны
  - Остальные = скрыты до раскрытия

### 5.4 Анимация движения
```
Клик на выход
  ├─ Player перемещается (0.2s, cubic ease-in-out)
  ├─ Камера с отставанием (0.05s задержка + 0.3s движения)
  └─ Видимость нового тайла обновляется
```

### 5.5 Боевая система
- **Запуск:** `GameManager.start_monster_battle()` формирует контекст боя (`player`, `monster`, `from_tile`, `battle_type`) и переводит `state = GameState.BATTLE`, при этом `_battle_in_progress` устанавливается в `true` и рассылается `battle_state_changed(true)`.  
- **Фазы:** `BattleStateMachine` выполняет PrepareBattle → (внезапный бой сразу → PlayerChoice, обычный бой → DiceCheck) → PreparePlayerChoice → PlayerChoice → (в зависимости от выбора: повторный DiceCheck или переход в PrepareEndBattle) → EndBattle.  
- **Dice Check:** `DiceCheckState` вызывает `run_dice_game(player, monster)` через `dice_game_ui_scene` или fallback генерацию (roll 1..6). Результат сохраняется в контексте, косвенно определяя, попадет ли игрок в `PlayerChoice` или сразу завершит бой.  
- **Player Choice:** игрок видит `PlayerUI` / `RoomUI` в боевом режиме и выбирает между `fight` и `run`. При `fight` снова срабатывает `DiceCheck`, при `run` выполняется `_apply_run_away_penalty` (анимация, −1 HP, монстр получает доступ к тайлу) и переходит в PrepareEndBattle.  
- **Завершение:** `PrepareEndBattleState` вызывает `handle_monster_death` или `handle_player_death`, ждет `hide_battle_ui`, а `EndBattleState` вызывает `finalize_battle`. После этого `GameManager._finish_battle()` возвращает UI в `GameState.DAY`, сбрасывает `_battle_ctx` и сообщает `player_ready_after_battle`, чтобы связанный тайл мог вернуть игрока на карту.
- **Разница с прежней версией:** до v1.2 монстры только лишали ОД и повреждений без чеков или UI, теперь есть полноценный цикл с состояния, отдающим контроль игроку, и штрафом за бегство.

### 5.6 Кнопка «Закончить ход» и PlayerUI
- **В прошлом:** `HUD` показывал кнопку только при 0 ОД, не учитывая, что игрок может быть в битве.  
- **Сейчас:** `UI` следит за `battle_state_changed` и `is_battle_active()`, чтобы отключить кнопку и запретить `request_player_finish_turn()` на время боя. `PlayerUI.hide()` теперь защищает от повторного вызова анимации (если она уже запущена, новые вызовы игнорируются), а асинхронное ожидание `await get_tree().process_frame` в `PlayerChoiceState` гарантирует, что UI показывается после внезапных боев. Это устраняет рассинхронизацию между визуальной панелью и новым состоянием битвы.

---

## 6. ГРАФ ГЕНЕРАЦИИ ТАЙЛОВ

### Алгоритм BFS-соединения:

```
1. Создание кругов (красный + 3 зелёных)
2. Установка 4 выходов на красный, 1 на каждый зелёный
3. BFS от зелёных + красный:
   - Добавляем соседей непосещённых в очередь
   - Если тайл без выходов → создаём к соседу
4. Если есть непосещённые → create_path_between() от них к красному
5. add_random_exits() → 15% шанс добавить выход (max 4 на тайл)
6. _constrain_green_exits() → зелёные остаются с 1 выходом
```

### Важные инварианты:
- **Каждый тайл достижим** из красного (гарантировано путём)
- **Каждый зелёный имеет ровно 1 выход** (выбирается в сторону красного)
- **Выходы двусторонние** (если A→B то B→-A)
- **Максимум 4 выхода** на один тайл (UP, DOWN, LEFT, RIGHT)

### 6.1 Типы комнат и веса
- В `scripts/core/Tile.gd` объявлен `RoomType` (EMPTY, CHEST, AMBUSH, MONSTER) и `ROOM_TYPE_WEIGHTS`, которые становятся входными данными для системы визуала и возможных событий. В v1.0–v1.1 `weight` для сундуков и засад был 0, поэтому такие комнаты не появлялись. В текущем состоянии (v1.2) веса выставлены как 0.2/0.2/0.2/0.4, что даёт шанс 60% на отличные от обычного монстра тайлы, но при этом сохраняет доминирование врагов. Это влияет на плотность лута / ловушек на этапе генерации и требует, чтобы LevelManager учитывал дополнительные состояния (например, блокировка выхода для `AMBUSH`).

---

## 7. КРИТИЧЕСКИЕ ЗАВИСИМОСТИ И УЗКИЕ МЕСТА

### 7.1 Взаимозависимости
```
GameManager
  ├─ требует LevelManager (через get_first_node_in_group)
  ├─ требует CameraDrag (через group)
  └─ зависит от Player.action_points

LevelManager
  ├─ инстанцирует Tile и Player
  └─ вызывает GameManager.game_loaded_full()

Player
  ├─ требует LevelManager.tiles (получает через initialize_on_tile)
  ├─ требует CameraDrag (через group или путь)
  └─ зависит от Tile.exit_clicked сигнала

Tile
  └─ требует GameManager (через group для active_player)

CameraDrag
  └─ требует Player (через group для active_player)

BattleStateMachine
  ├─ инстанцируется GameManager и получает `_deps` (show/hide BattleUI, enter/exit RoomUI, run_dice_game, apply_damage/run_penalty, finalize_battle)
  ├─ зависит от наличия `BattleUI.tscn`, `RoomUIController` и `dice_game_ui_scene` для визуальной части и взаимодействия с игроком
  └─ по завершению эмитит `battle_finished`, который обрабатывает `_finish_battle()` в GameManager
```

### 7.2 Точки отказа (Single Points of Failure)

1. **group "game_manager" не установлена** → CameraDrag, Tile, Player, LevelManager не найдут GameManager → no input processing
2. **LevelManager.tiles == empty** → Player.move_to_tile() вернёт false на проверке `if not level_manager.tiles.has(next_pos)`
3. **CameraPivot или Camera3D отсутствуют** → ошибка в CameraDrag._ready(), но не критична (returns)
4. **Зелёные тайлы не созданы** → LevelManager.create_players() выводит ошибку, players не создаются
5. **IntroCutScene не найдена** → fallback на preload, если preload не найдена → intro_finished() вызывается сразу
6. **BattleUI / DiceGameUI отсутствуют или не содержат ожидаемые методы (`run_battle`, `AnimationPlayer`)** → `BattleStateMachine` продолжает ожидать входа от UI, но игроку нечем управлять → `start_monster_battle()` не освобождает `GameState.BATTLE`. Рекомендуется логировать отсутствие UI и досрочно завершать состояние.

### 7.3 Предположения в коде

1. **LevelManager инициализируется до GameManager.game_loaded_full()** → иначе tiles.size() == 0
2. **Player.level_manager устанавливается до initialize_on_tile()** → иначе next_tile lookup падает
3. **Активный игрок == на актуальном тайле** → код в Tile.on_player_entered() не синхронизирует, могут быть рассинхроны
4. **Все тайлы существуют при create_grid()** → если radius < 1, компенсируется `radius = 1`
5. **Маркеры выходов пересоздаются полностью** → старые удаляются, новые создаются (дорого, но безопасно)
6. **BattleStateMachine получает все зависимые callables** → отсутствие одного ключа (`run_dice_game`, `enter_battle_room_ui`, `finalize_battle` и т.д.) оставит FSM без визуального эффекта и может повиснуть между состояниями.
7. **dice_game_ui_scene.run_battle возвращает массив бросков** → если вернётся пустой массив, `DiceCheckState` будет читать 0 и бой пойдёт с минимальными шансами на победу.

---

## 8. ЖЁСТКИЕ ЗНАЧЕНИЯ И ИХ ВЛИЯНИЕ

### Система времени / анимации
| Значение | Место | Эффект |
|----------|-------|--------|
| 0.2s | Player.MOVE_DURATION | Скорость анимации шага |
| 0.3s | Player.CAMERA_MOVE_DURATION | Скорость анимации камеры |
| 0.05s | Player.CAMERA_DELAY | Отстав камеры за игроком |
| 2s | GameManager.TURN_SWITCH_DELAY | Пауза между ходами |
| 0.15s | PlayerUI.PORTRAIT_TWEEN_DURATION | Масштабирование портрета |

**Влияние:** Если увеличить задержки → игра будет медленнее, но сценарий читаться лучше.

### Геймплей / Баланс
| Значение | Место | Эффект |
|----------|-------|--------|
| 3 | Player.MAX_ACTION_POINTS | Шагов в день на игрока |
| 9 | LevelManager.circle_radius | Размер лабиринта (красный круг) |
| 5 | LevelManager.green_circle_radius | Размер финишных кругов |
| 0.05, 0.20, 0.60, 0.15 | exit_chance_* | Вероятность 1, 2, 3, 4 выходов |
| 0.15 | add_random_exits() | Шанс добавить доп. выход |

**Баланс:** Больше MAX_ACTION_POINTS → легче; меньше circle_radius → меньше тайлов.

### Визуальные константы
| Значение | Место | Эффект |
|----------|-------|--------|
| 4 | TILE_SIZE | Масштаб мировых координат |
| 0.3 | EXIT_MARKER_SIZE | Размер кубика выхода |
| 0.9 | EXIT_OFFSET | Расстояние от центра тайла |
| 1.0 | PLAYER_SIZE | Высота спрайта игрока |

---

## 9. СКРЫТЫЕ ДОПУЩЕНИЯ И НЕОГОВОРЕННЫЕ ПРАВИЛА

1. **Игрок не может "выйти из карты"** → проверка `tiles.has(next_pos)` гарантирует это
2. **Тайлы создаются одновременно** → но видимы только красный + зелёные, остальные скрыты
3. **Кольцо из зелёных = симметричное распределение** → `_pick_green_tile_positions()` выбирает по углам, но может быть смещено
4. **Красный тайл ВСЕГДА в центре (0,0)** → жёстко захардкодировано в create_grid()
5. **Между игроками есть фиксированный порядок** → players[0] → players[1] → players[2]
6. **Новый день = автоматический рефилл ОД** → нет промежуточного UI выбора
7. **Камера пресет 0 = "follow" режим** → на остальных можно перемещать мышью
8. **Портреты создаются на основе PlayersViewParams** → если метаданные не установлены → пусто

---

## 10. ДИАГРАММА СОСТОЯНИЙ

```
┌─────────────────────────────────────────┐
│   INIT: LevelManager.create_grid()      │
│   ├─ Генерация кругов                   │
│   ├─ Создание графа BFS                 │
│   └─ create_players() → 3 Player        │
└──────────────────┬──────────────────────┘
				   │
		call: game_loaded_full()
				   │
				   ▼
┌─────────────────────────────────────────┐
│   INTRO: IntroCutScene.play_intro()     │
│   ├─ Camera собственная                 │
│   ├─ Animation: intro_camera_out        │
│   └─ emit: intro_animation_finished     │
└──────────────────┬──────────────────────┘
				   │
	call: intro_finished()
				   │
				   ▼
┌─────────────────────────────────────────┐
│   TRANSFER: GameManager.game_started()  │
│   ├─ UI show                            │
│   ├─ Camera enabled = true              │
│   └─ _start_first_day()                 │
└──────────────────┬──────────────────────┘
				   │
				   ▼
		┌──────────────────────┐
		│  GAME DAY LOOP       │
		│ (повтор каждый день) │
		│                      │
		│  active_player[i]    │
		│  - Каждый ход:       │
		│    action_points -= 1│
		│  - После 3 кликов:   │
		│    finished_moving() │
		│                      │
		│  current_player_     │
		│  finished_moving()   │
		│  - wait 2s           │
		│  - next player       │
		│  - if all done:      │
		│    start_new_day()   │
		│                      │
		│  day += 1            │
		│  refill APs (3)      │
		│  restart from [0]    │
		└──────────────────────┘
```

---

## 11. ПРОБЛЕМНЫЕ МЕСТА И ФРАГИЛЬНОСТЬ

### Высокий риск:

1. **Синхронизация Player.current_tile с Tile.on_player_entered()** 
   - Player может быть физически не на тайле, если `current_tile` не обновлена
   - Масштабирование портрета происходит ПОСЛЕ смены active_player, но ПЕРЕД move_to_tile()
   - **Рекомендация:** Добавить явную синхронизацию после каждого move_to_tile()

2. **LevelManager.green_tile_positions может быть пуста**
   - Fallback есть, но только 1 тайл, что может вызвать скопление всех 3 игроков на одном
   - **Рекомендация:** Гарантировать минимум 3 зелёных тайла или увеличить radius

3. **GameManager.game_loaded_full() + intro_started + intro_completed = 3 флага**
   - Логика сложная, легко попасть в неправильное состояние
   - **Рекомендация:** Использовать FSM (State Machine)

4. **CameraDrag._process() работает каждый frame**
   - Интерполяция зума может быть затратной, если много объектов
   - **Рекомендация:** Добавить check на изменение target_* перед интерполяцией

5. **Path debug lines создаются ВСЕ при каждом вызове build_path_debug_lines()**
   - Для большого лабиринта → сотни MeshInstance3D
   - **Рекомендация:** Кэшировать или использовать единый Mesh с LineDrawer

6. **BattleStateMachine полагается на асинхронные интерфейсы**
   - `start_monster_battle()` ждёт `_battle_state_machine.start()`, а тот `await`-ит `show_battle_ui()`, `run_dice_game()` и `play_camera_hit()`. Если UI-сцены не инстанцируются или не выдаются события `player_choice`, `_battle_in_progress` остаётся `true`, игрок не может закончить ход, а `GameState` застревает в `BATTLE`.
   - **Рекомендация:** Добавить проверку `_deps`, тайм-ауты и fallback-UI, логировать сбои и принудительно завершать бой при отсутствии ответа.

### Средний риск:

6. **Тайлы скрыты, но физика на них ещё активна**
   - Area3D.input_ray_pickable остаётся true даже при hide_tile()
   - **Эффект:** Можно кликать через стены на скрытые выходы
   - **Рекомендация:** Отключать CollisionShape3D при hide_tile()

7. **Экспортируемые вероятности в LevelManager должны суммироваться в 1.0**
   - Если exit_chance_* не равны 1.0 → неопределённое поведение в set_tile_exits()
   - **Текущее значение:** 0.05 + 0.20 + 0.60 + 0.15 = 1.0 ✓ (OK)

8. **Player.previous_tile не сбрасывается при смене дня**
   - Если игрок был на тайле [N], перешёл на [N+1], а новый день начался
   - `previous_tile` ещё указывает на старый тайл другого дня
   - **Рекомендация:** Сбрасывать previous_tile в initialize_on_tile()

### Низкий риск:

9. **Почти все get_node_or_null() возвращают null без пробросания ошибки**
   - Graceful fallback работает, но может скрыть проблемы в сцене
   - **Рекомендация:** На prod добавить логирование

---

## 12. РЕЗЮМЕ

### Тип игры:
Процедурная **пошаговая roguelike** на **3D-сетке** с простой механикой движения и ресурсным лимитом (ОД).

### Архитектурный паттерн:
**Event-driven** (Godot signals) + **Manager pattern** (GameManager как центральный оркестратор).

### Сильные стороны:
✅ Модульная структура (LevelManager, Player, Tile, GameManager — независимы)  
✅ Процедурная генерация гарантирует достижимость цели  
✅ Плавные анимации с правильным easing  
✅ Простая, понятная механика  
✅ `BattleStateMachine` и обновлённый UI/PlayerUI позволяют плавно включать бой, показывать Dice Check и очищать состояние без жёсткой сцепки с каждым компонентом

### Слабые стороны:
❌ FSM для состояния игры разбросана по флагам  
❌ Синхронизация активного игрока между компонентами неявная  
❌ Нет явной обработки ошибок (много fallback'ов)  
❌ Vis-а-vis скрытые тайлы всё ещё интерактивны  
❌ Path debug lines создаются наивно (много объектов)  
❌ Новая битва зависит от множества делегатов и UI-сцен (BattleUI, DiceGameUI, RoomUI), и без них `GameManager` останется в `GameState.BATTLE`

### Где логика может сломаться:
1. Отсутствие group "game_manager" → весь ввод падает
2. LevelManager.create_grid() не вызвана → no tiles
3. Player.level_manager не установлена → NPE при move_to_tile()
4. Синхронизация player/tile стейта при быстрых кликах
5. Отсутствие или падение `BattleUI`/`DiceGameUI` → `BattleStateMachine` не получает выбор игрока и оставляет `GameState.BATTLE`

---

## ИСТОРИЯ ДОКУМЕНТА

- **v1.2** (04.02.2026) - Добавлены подробности боевой FSM (battle/dice/ui), новый сигнал `battle_state_changed`, переосмыслен `PlayerUI`/HUD, увеличены веса `RoomType` и собрано описание уязвимых зависимостей.
- **v1.1** (25.01.2026) - Обновлена секция CameraDrag: актуальны четыре пресета, базовая скорость скролла и API центрации.
