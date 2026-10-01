# vibes-game

Co-op friendslop games, each one its own engine project.

```
godot/
  engine/     put the Godot 4.7.2 editor here (godot.exe; not committed)
  Mushroom/   Godot project: Mushroom Foraging
  TV/         Godot project: STANDBY... GO! (live TV studio + theatre)
Unreal/       empty for now
Unity/        empty for now
docs/         design docs and scenario write-ups
```

## Play / edit (Godot)

1. Get **Godot 4.7.2** (standard build, not .NET) from
   [godotengine.org](https://godotengine.org/download) and put `godot.exe` in `godot/engine/`.
2. Open it, click **Import**, pick `godot/Mushroom/project.godot` or `godot/TV/project.godot`.
3. Press **F5**.

Multiplayer: one player clicks **Host**, the others type the host's IP and click **Join**
(UDP port 7777). Over the internet, the host forwards UDP 7777, or everyone joins the same
Tailscale / ZeroTier / Radmin VPN and uses the host's VPN IP.

Testing alone with two windows: in the editor, **Debug → Customize Run Instances**, enable 2
instances, give one `-- --host --name=Adam` and the other `-- --join=127.0.0.1 --name=Denis`.

Each game is fully self-contained: copy one folder anywhere and it opens. Art credits are in each
game's `CREDITS.md` (all free CC0 assets, mostly [Kenney](https://kenney.nl)).

## Mushroom Foraging (`godot/Mushroom`)

Four friends lost their jobs and now live in a junk camp in the forest. They pick weird mushrooms,
taste them to find out which are safe, and sell the safe ones in the village.

- **The map**: junk camp in the middle; a dirt road to the village (Horná Lehota) and the casino;
  footpaths to the witch's graveyard and an old ruin; a lake (you can drown) and a cliff (you can
  fall). Drive there in the car (E to get in, first one in drives).
- **Mushrooms**: 12 species, six look-alike pairs plus crazy ones (glowcap, rainbow bolete, golden
  chanterelle, screaming puffball, devil's cigar, witch's finger). F tastes the one you hold and
  identifies the species for everyone (J opens the journal). Results: fine / trip / pass out /
  poisoned (90 s to get a medkit, or you die). Turn a held one with R or the mouse wheel; throw one
  hard three times and it breaks.
- **Money**: drop mushrooms in the basket, carry or drive it to Babka Hela at the village market.
  She only buys identified, safe-to-sell species. Jano's shop sells medkits and batteries. The
  house plot at camp builds a house (boars stay out of camp). The casino has slot machines; an old
  slot machine sits at the ruin, carry it home and spin it there for random stuff.
- **Days and nights**: a round is one day (10 min), then it gets properly dark. T is the
  flashlight (batteries run out). Wild boars hunt at night.
- **Dying**: poison, falling, drowning, getting run over, crashing the car, boars. The dead float
  around as ghosts until the witch revives them (bring the basket with 2 Witch's fingers and
  1 Glowcap).
- Controls: WASD, Shift sprint, Space jump / swim / brake, E grab / use / car, Q throw,
  F taste / use, R or wheel turn what you hold, H medkit (on who you look at, else yourself),
  T flashlight, J journal, Esc frees the mouse.

## STANDBY... GO! (`godot/TV`)

You and your friends are the crew of a live show. The audience only sees what's on camera or on
stage; everything behind it is chaos. The menu has a **RULES & CONTROLS** screen.

- **We're Live! (TV studio)**: Channel 6 evening news. One anchor at the desk, the rest run the
  show: three studio cameras (E to operate, mouse to aim, wheel to zoom), the control desk
  (TAKE cameras 1-4, REC, type the teleprompter / subtitles live), a weather green screen and an
  interview corner. Every round a **BREAKING NEWS** story drops (a shark loose downtown, the last
  potato, a shopping-cart rampage...): grab the FIELD CAM by the exit, go out into the city, find
  it and get it on air. Ratings drop on dead air and crew in shot; the recorded tape plays back at
  the end.
- **Places, Please! (theatre)**: backstage crew of a live play: an actor on the star during scenes,
  and in each blackout the set (tree, castle wall, throne) moved onto the glowing marks.
- The set is full of grabbable nonsense: potatoes, a brick, tyres, a shopping cart, a watermelon...

## Docs

- `docs/scenarios/` - one imagined round of each game.
- `docs/design/` - pitch, GDD, mode ideas, art direction, roadmap from the research session.
