class_name PracticeClock
extends RefCounted
## A practice session's PLAY time (docs/ADS.md → Practice, Ross 2026-11-12):
## the seconds the run was live, for the one chance at an ad on the way out.
## The screen ticks it with the frame's delta only while the run is live (the
## tree's pause stops the frames; the first-shot lesson is skipped by the
## caller); `suspend` / `resume` bracket the app's time in the background. A
## frame longer than MAX_FRAME_S is a stall or a resume, not play, and counts
## as MAX_FRAME_S. Headless.

## The longest a frame may count for.
const MAX_FRAME_S := 0.25

var seconds := 0.0
var suspended := false


func tick(dt: float) -> void:
	if suspended or dt <= 0.0:
		return
	seconds += minf(dt, MAX_FRAME_S)


## The app went to the background: nothing counts until `resume`.
func suspend() -> void:
	suspended = true


func resume() -> void:
	suspended = false


## A new session.
func reset() -> void:
	seconds = 0.0
	suspended = false
