extends Node3D

signal pressed

@export var text: String = "Открыть"

@onready var viewport := $ButtonViewport
@onready var button := viewport.get_node_or_null("ButtonLayer/Button") as Button
@onready var display := $ButtonDisplay as Sprite3D

func _ready():
	_update_button_text()
	_update_display_texture()
	if button and not button.is_connected("pressed", Callable(self, "_on_button_pressed")):
		button.pressed.connect(Callable(self, "_on_button_pressed"))
	button.visible = false

func show_button() -> void:
	if button:
		button.visible = true

func hide_button() -> void:
	if button:
		button.visible = false

func _update_button_text() -> void:
	if button:
		button.text = text

func _update_display_texture() -> void:
	if display and viewport:
		var texture: Texture2D = viewport.get_texture() as Texture2D
		if texture:
			display.texture = texture

func _on_button_pressed() -> void:
	emit_signal("pressed")
