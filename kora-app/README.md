# Kora

Garmin FR165 activity app that counts circumambulations (kora) of a chorten.

- **START** to start: your position is locked as the start point.
- Round 1: once you have gone more than 2 × the radius away and come back within the radius, the count goes up by 1, the watch buzzes and a lap is added. Round 1 also learns the chorten's centre and your walking direction.
- Round 2 on: a start line runs from the centre out through the start point. Each full turn in your walking direction counts, however far in or out you pass the start. Walking back over the line doesn't count.
- **BACK** while recording counts a round by hand, for when GPS is blocked (roofed prayer-wheel corridors).
- **START** again to pause, then Resume, Save or Discard. The activity saves as a walk with a `rounds` field.
- **UP / DOWN** before START: choose a goal: No goal (default), 3, 7, 13, 21 or 108.
- Outer ring with a goal: fills towards it (one segment per round up to 21); long-short-long buzz when reached.
- Outer ring with no goal: a dot shows where you are round the circuit. The centre and walking direction are learned on round 1, so the dot appears from round 2.
- Watermark: `tools/jangchub-chorten.png` (supplied line art), dimmed by `tools/render.py`.
- Settings (Connect IQ app): goal, and start-circle radius 5 / 8 / 12 / 20 m (default 8). Use 5 m for small chortens and 20 m for long kora paths.

Build: `monkeyc -f monkey.jungle -d fr165 -o bin/kora-fr165.prg -y ../developer_key -l 2`
Test: add `-t`, then `monkeydo bin/kora-fr165.prg fr165 -t`
Simulate: Simulator → Simulation → Activity Data → load `tools/kora-3-rounds.gpx` (3 rounds round the Memorial Chorten, Thimphu).
Art: `python3 tools/render.py` (watermark + launcher icon from the chorten image).
