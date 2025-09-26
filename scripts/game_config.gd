extends Node

# Global game configuration accessible via autoload
# Usage: GameConfig.mode = GameConfig.Mode.SINGLEPLAYER

enum Mode { SINGLEPLAYER, MULTIPLAYER }

var mode: int = Mode.MULTIPLAYER

# Map of peer_id -> role string ("defender" | "thrower")
var roles: Dictionary = {}

func clear_roles() -> void:
	roles.clear()

# Future extension points
var difficulty: String = "normal"  # easy, normal, hard

# Presentation toggles
var presentation_pack: bool = true
