# M2 Stage 2 Run/Map/Save Runbook

The M1 baseline is Git commit `7b16aec` and passed both original headless tests before M2 work began.

## Headless verification

Run each command from Windows/WSL with Godot 4.7:

```bash
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/m1_smoke_test.gd
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/seed_regression_test.gd
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/m1_boundary_test.gd
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/m2_content_validation_test.gd
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/m2_map_test.gd
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/m2_save_rng_test.gd
```

## Determinism contract

- `map_rng`, `combat_rng`, `reward_rng`, `event_rng`, and `shop_rng` are independently SHA-256-derived.
- Every snapshot stores `algorithm`, `seed`, `draw_count`, and engine `state`; restoration uses `state`.
- Godot's JSON parser cannot round-trip arbitrary signed 64-bit numbers. The on-disk snapshot therefore also carries internal decimal `seed_exact`/`state_exact` fields; load restores the required numeric fields from them and removes the transport fields before exposing `RunState`.
- Map candidates and encounter pools are sorted before random selection.
- `SaveManager` writes a checksummed temporary file, flushes it, rotates the previous save to `.bak`, and atomically renames the temporary file.
- A corrupt primary can explicitly recover `.bak`; unsupported newer or unmigrated older schemas return structured errors without overwriting files.
