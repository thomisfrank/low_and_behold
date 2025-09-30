extends Node

# Smoke test: loads key GDScript files to catch compile/load errors.
# Run with: godot --no-window --scene tools/smoke_test.tscn OR --script tools/smoke_test.gd

func _ready():
	var paths = [
		"res://scripts/Deck.gd",
		"res://scripts/GameManager.gd",
		"res://scripts/CardDrawAnimation.gd",
		"res://scripts/PlayerHand.gd",
		"res://scripts/opponent_hand.gd",
	]
	var ok = true
	for p in paths:
		print("[smoke] Loading ", p)
		var r = load(p)
		if not r:
			print("[smoke][ERROR] Failed to load: ", p)
			ok = false
		else:
			# Try to instantiate if it's a scene or class
			var inst = null
			if r is PackedScene:
				inst = r.instantiate()
			elif r is GDScript:
				# instantiate if possible
				if r.can_call("new"):
					inst = r.new()
			if inst:
				print("[smoke] Instantiated: ", p, " -> ", inst)
			else:
				print("[smoke] Loaded: ", p)

	if ok:
		print("[smoke] All key scripts loaded successfully.")
	else:
		print("[smoke] Some scripts failed to load. See errors above.")

	get_tree().quit()
