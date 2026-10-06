extends RefCounted
## Backoff (docs/BACKEND.md → Throttling, layer 1): doubling delays with
## jitter, a cap, Retry-After winning, and the minimum-gap check.


func run(t) -> void:
	t.close(Backoff.next_delay(0), 2.0, 1e-9, "the first retry waits 2 s")
	t.close(Backoff.next_delay(1), 4.0, 1e-9, "then 4")
	t.close(Backoff.next_delay(2), 8.0, 1e-9, "then 8")
	t.close(Backoff.next_delay(20), Backoff.CAP_S, 1e-9, "capped at five minutes")
	t.close(Backoff.next_delay(3, -1.0, 0.0), 16.0 * 0.75, 1e-9, "jitter low: −25 %")
	t.close(Backoff.next_delay(3, -1.0, 1.0), 16.0 * 1.25, 1e-9, "jitter high: +25 %")
	t.close(Backoff.next_delay(0, 37.0), 37.0, 1e-9, "Retry-After wins")
	t.close(Backoff.next_delay(0, 0.0), 1.0, 1e-9, "…with at least a second's grace")
	t.ok(Backoff.next_delay(-5) >= 2.0, "a negative attempt counts as the first")
	t.ok(Backoff.can_fire(100.0, -1.0, 30.0), "never fired → may fire")
	t.ok(not Backoff.can_fire(100.0, 80.0, 30.0), "20 s after the last with a 30 s gap → not yet")
	t.ok(Backoff.can_fire(110.0, 80.0, 30.0), "30 s later → go")
