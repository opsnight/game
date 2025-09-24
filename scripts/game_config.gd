extends Node

# Global game configuration accessible via autoload
# Usage: GameConfig.mode = GameConfig.Mode.SINGLEPLAYER

enum Mode { SINGLEPLAYER, MULTIPLAYER }

var mode: int = Mode.MULTIPLAYER

# Future extension points
var difficulty: String = "normal"  # easy, normal, hard
