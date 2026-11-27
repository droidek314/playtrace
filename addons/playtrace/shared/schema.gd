class_name PlaytraceSchema
extends RefCounted
## Session file format constants (schema v1, contract section 5).
##
## Use these instead of string literals when writing or reading events,
## so runtime, editor and tools never drift apart.

## Current schema number written in the session header.
const VERSION := 1

## Header line type.
const SESSION_START := "session_start"
## Level entered.
const LEVEL_ENTER := "level_enter"
## Level left.
const LEVEL_EXIT := "level_exit"
## Periodic player position.
const POS := "pos"
## Player died.
const DEATH := "death"
## Player stuck in place.
const STUCK := "stuck"
## Checkpoint reached.
const CHECKPOINT := "checkpoint"
## Level completed.
const LEVEL_COMPLETE := "level_complete"
## Game quit.
const QUIT := "quit"
## Game-defined event.
const CUSTOM := "custom"
## In-game feedback submitted.
const FEEDBACK := "feedback"

## Setup health warning: no player node was found (detection.player is "").
const WARN_PLAYER_NOT_FOUND := "player_not_found"
## Setup health warning: the tracked node never moved more than 2 px in a session.
const WARN_PLAYER_NEVER_MOVED := "player_never_moved"
## Setup health warning: a level was re-entered 3+ times across sessions but 0 deaths were recorded.
const WARN_RELOADS_WITHOUT_DEATHS := "reloads_without_deaths"

## Default directory for local session files.
const SESSIONS_DIR := "user://playtrace/sessions"
