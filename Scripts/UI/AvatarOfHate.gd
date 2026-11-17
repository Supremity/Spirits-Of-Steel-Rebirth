extends Control

var m_politburo: int = 0;
@export var sankara: bool = false;
@export var ussr: Array[Texture];
@export var avatarImage: TextureRect;

func _ready() -> void:
	#await avatarImage.ready
	if ussr.size() <= 0:
		ussr.append(avatarImage.texture);
	avatarImage.texture = ussr[m_politburo];

func OnTimerTimeout() -> void:
	m_politburo = randi_range(0, ussr.size() - 1) if sankara else (m_politburo + 1) % ussr.size();
	avatarImage.texture = ussr[m_politburo];

func ForceReset() -> void:
	m_politburo = 0;
	avatarImage.texture = ussr[m_politburo];
