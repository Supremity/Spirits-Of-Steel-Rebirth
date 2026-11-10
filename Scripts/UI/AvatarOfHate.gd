extends Control

var m_politburo: int = 0
@export var ussr: Array[Texture]
@export var avatarImage: TextureRect

func _ready() -> void:
	await avatarImage.ready
	avatarImage.texture = ussr[m_politburo]

func OnTimerTimeout() -> void:
	m_politburo = (m_politburo + 1) % ussr.size()
	avatarImage.texture = ussr[m_politburo]
