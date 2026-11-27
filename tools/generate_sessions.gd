extends SceneTree
## Command-line wrapper around [PlaytraceSessionGenerator] (contract 6.5).
##
## Usage:
## [codeblock]
## godot --headless --script tools/generate_sessions.gd -- --seed 1 --count 200 \
##     --level res://demo/sandbox.tscn --out user://playtrace/sessions
## [/codeblock]


func _init() -> void:
	var opts := {"seed": "1", "count": "200", "level": "res://demo/sandbox.tscn", "out": PlaytraceSchema.SESSIONS_DIR}
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		var key := args[i].trim_prefix("--")
		if not opts.has(key):
			push_warning("Playtrace: unknown option %s" % args[i])
			quit(2)
			return
		opts[key] = args[i + 1]
	var n := PlaytraceSessionGenerator.new().write(int(opts["seed"]), int(opts["count"]), opts["level"], opts["out"])
	print("Playtrace: generated %d sessions in %s" % [n, opts["out"]])
	quit(0 if n > 0 else 1)
