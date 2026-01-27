class_name GameConfig
extends RefCounted

# === Тайлы ===
const TILE_SIZE := 4

# === Движение / камера ===
const PLAYER_MOVE_DURATION := 0.2
const CAMERA_MOVE_DURATION := 0.3
const CAMERA_DELAY := 0.05

# === Очки действий ===
const MAX_ACTION_POINTS := 3
const MIN_ACTION_POINTS := 0

# === Тайминги игры ===
const TURN_SWITCH_DELAY := 2.0
const NIGHT_DELAY := 2.0

# === Визуальные параметры тайлов ===
const EXIT_MARKER_SIZE := Vector3(0.3, 0.3, 0.3)
const EXIT_OFFSET := 0.9
const HOVER_SCALE := 1.2
const NORMAL_SCALE := 1.0
const GATE_COLOR_ACTIVE := Color(0.2, 1.0, 0.2)
const GATE_COLOR_INACTIVE := Color(0.5, 0.5, 0.5)
