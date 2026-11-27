class_name PlaytraceStuckDetector
extends RefCounted
## Finds "stuck" periods: the player stays within [member radius_px] of one spot for at least
## [member threshold_ms] of unpaused time.
##
## Approach: keep an anchor point. While the player stays within the radius of the anchor,
## unpaused time accumulates (so small jitter still counts as stuck). When the player leaves
## the radius, the period ends: if it lasted long enough, one stuck event is reported with the
## anchor position and the total seconds, and a new anchor starts at the current position.
## Reporting at the end (not at the threshold) gives the real duration in one event.

## Movement radius in pixels that still counts as standing in one place.
var radius_px := 16.0
## Unpaused milliseconds inside the radius before a period counts as stuck.
var threshold_ms := 8000

var _anchor := Vector2.INF
var _still_ms := 0


## Starts over at [param at] (Vector2.INF = at the next position seen).
func reset(at: Vector2 = Vector2.INF) -> void:
	_anchor = at
	_still_ms = 0


## Feeds one frame. Returns {"p": Vector2, "seconds": float} when a stuck period just ended, else {}.
func step(pos: Vector2, dt_ms: int, paused: bool) -> Dictionary:
	if _anchor == Vector2.INF:
		_anchor = pos
		return {}
	if pos.distance_to(_anchor) >= radius_px:
		var ended := finish()
		reset(pos)
		return ended
	if not paused:
		_still_ms += dt_ms
	return {}


## Ends the current period (death, level change, quit). Returns the stuck event data or {}.
func finish() -> Dictionary:
	var ended := {}
	if _still_ms >= threshold_ms:
		ended = {"p": _anchor, "seconds": snappedf(_still_ms / 1000.0, 0.1)}
	_still_ms = 0
	return ended
