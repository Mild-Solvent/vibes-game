# Art direction (draft for the artist to own and overrule)

This is a starting point. The artist decides the final style.

## Constraints that matter for gameplay
- **Low-poly, flat or low-texture 3D.** Cheap to produce, runs on weak PCs, and fits the genre.
- **Readable on a stream at 720p.** Silhouettes and colour blocks over detail.
  Labels like tape names, rope numbers and sound buttons must be readable, which means
  a **big chunky font on props**.
- **Front vs. back contrast is the core visual idea:**
  - *Front* (on camera / on stage): saturated, warm, clean, well-lit, a "TV perfect" look.
  - *Back* (control room, wings, fly loft): dim, cool blue work lights, cables, gaffer
    tape, clutter, glow tape.
  - The camera feed / audience view can use a post-process filter (broadcast scanlines
    for TV, a warm spotlight vignette for theatre) so The Tape looks different from gameplay.
- **Crew characters:** simple body, expressive head, one big readable accessory
  (headset). Customisable colours and hats are the cosmetic economy. They need to look
  funny when ragdolling (R.E.P.O. and Peak both nail this).
- **NPC talent/actors:** slightly more "polished" than the crew, as if they're the stars.
  That makes it funnier when they fall over.

## Reference board (to collect)
R.E.P.O. robots (silly, readable), Peak scouts, Untitled Goose Game / Big Walk
(flat colour, clean), Content Warning (the low-fi camera feed), *Noises Off* (the play:
a farce seen from backstage), *The Play That Goes Wrong*, and real control rooms and
fly galleries.

## Tech constraints (for the pipeline)
- Blender → FBX into Unity (engine pending, see engine-decision.md)
- Metric scale, 1 unit = 1 m, Y-up on export, origin at the base of the object
- Aim for under 3k tris per prop, under 8k per character. Shared texture atlases/palettes are preferred
- Physics props need a simple collision shape (box/capsule). The artist can just
  make a rough low-poly "collider mesh" named `*_COL`
- Naming: `prop_vt_tape`, `set_newsdesk`, `char_crew_base`, `fx_fog`
