class_name PlaytraceSessionWriter
extends RefCounted
## Appends events to one session file (JSON Lines, schema v1).
##
## Lines are buffered in memory and written + flushed to disk on [method flush], which the
## recorder calls every 5 s and on level_exit / quit, so a crash loses at most 5 s.

## Path of the open session file.
var path := ""

var _file: FileAccess
var _buffer := PackedStringArray()


## Creates the file (and its directory) at [param file_path]. Returns false if it cannot be opened.
func open(file_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	path = file_path
	return _file != null


## Queues one event line. Keys keep their insertion order.
func write(event: Dictionary) -> void:
	_buffer.append(JSON.stringify(event, "", false))


## Writes queued lines to the file and flushes it to disk.
func flush() -> void:
	if _file == null or _buffer.is_empty():
		return
	_file.store_string("\n".join(_buffer) + "\n")
	_buffer.clear()
	_file.flush()


## Flushes and closes the file. Safe to call twice.
func close() -> void:
	if _file == null:
		return
	flush()
	_file.close()
	_file = null


## Returns true while the file is open.
func is_open() -> bool:
	return _file != null
