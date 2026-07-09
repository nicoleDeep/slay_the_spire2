# M1 Combat Slice Runbook

## Run

Open `/mnt/d/project/slay-the-spire-2` with Godot 4.x and run the project. The main scene is `res://scenes/main/main.tscn`.

The main screen validates content and starts `res://scenes/combat/combat.tscn`. The combat scene starts a fixed-seed D1 fight with `ember_ranger` against `mote_biter`. Use the `D0` and `D1` buttons to compare difficulty profiles.

## Headless Smoke Test

If a Godot 4 binary is available:

```bash
godot --headless --path /mnt/d/project/slay-the-spire-2 --script res://scripts/tests/m1_smoke_test.gd
```

or:

```bash
godot4 --headless --path /mnt/d/project/slay-the-spire-2 --script res://scripts/tests/m1_smoke_test.gd
```

On the current Windows-mounted workspace, this form also works:

```bash
Godot_v4.7-stable_win64_console.exe --headless --path "D:\project\slay-the-spire-2" --script res://scripts/tests/m1_smoke_test.gd
```

## Scope

Implemented for M1:

- Data loader for JSON content.
- Content validator for Character/Card/Enemy/Difficulty data.
- Character, card, enemy, and difficulty schema skeletons.
- Explicit combat RNG stream with a serializable `{ seed, draw_count }` snapshot.
- D0/D1 `DifficultyProfile.base_adjustments`.
- Basic combat manager detached from UI.
- Draw pile, hand, discard pile, energy, block, damage, enemy intent, end turn, victory, and defeat.
- `damage`, `gain_block`, and `draw` ops.

Known M1 limits:

- Relics, rewards, map, shop, events, potions, and save files are not implemented yet.
- Boss phase filtering is implemented for weighted move selection; cooldown and max-consecutive move constraints are data-only for now.
- Status formulas are not active because Stage 1 content uses no status ops.
