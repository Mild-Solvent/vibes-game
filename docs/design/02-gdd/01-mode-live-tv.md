# Mode: We're Live! (TV news broadcast)

> You're the crew of Channel 6's live evening news. Nobody watches Channel 6. Tonight they will.

## Setting
One TV studio: a news desk, a weather green screen, an interview couch, and a control
room behind glass. There are also a loading dock, a makeup room, the vending machine
and a corridor to the roof (for "live on location" segments).

## Roles
| Role | Where | Job |
|---|---|---|
| **Anchor** | Desk, on camera | Read the teleprompter aloud, keep calm, cover for mistakes live |
| **Director** | Control room | Watches all camera feeds, calls cuts on headset, presses the TAKE button |
| **Prompter op** | Control room corner | **Types the teleprompter text live** (the core gag). The script arrives in chunks, and they can "improve" it |
| **Camera op ×1–2** | Studio floor | Push a physical camera on wheels, frame the shot, don't get in each other's shots |
| **Floor manager / props** | Studio floor | Hand props to the anchor, run the VT tapes, dress guests, deal with the random events |
| **Weather** (optional talent) | Green screen | Points at a map they can't see, relying on the monitor and the director's instructions |

At 2 players: Anchor + a "one-person crew" (auto-cameras, NPC prompter).

## Core loop per segment
1. The run-of-show says what's next (headlines → VT package → interview → weather → sign off).
2. The director calls the camera, the camera op frames it, the director presses TAKE.
3. The prompter op types what the anchor must read. The anchor reads whatever appears,
   exactly as written, and the **audience scores it**.
   Rule: the anchor *may* improvise, but reading the prompter scores safer.
4. The floor crew deals with the physical stuff: VT tapes, guests, props, fires.

## Signature gags
- **Prompter typos.** The anchor reads "the mayor has been ARSESTED". The game scores
  any on-air read, so a prompter op with bad intentions can feed the anchor anything.
  Guard rails: a banned-words filter bleeps it on the Tape, and there's a "the
  prompter op is fired" button, i.e. a vote-kick back to floor duty.
- **Wrong VT.** Tapes are physical props with hand-written labels. "CAT_TREE" vs
  "CAT_TREE_FINAL_v2". You find out on air.
- **Green screen.** The weather person can't see the map; they see only the monitor
  that the camera op keeps knocking.
  Anyone wearing green disappears. There's green paint in the props room.
- **The guest.** An NPC interview guest who is drunk, falls asleep, or has the wrong
  name on the lower third.
- **Dead air.** If the director doesn't TAKE a shot, the channel shows the
  "Technical difficulties" card, which is a meter drain and a Tape moment.
- **Breaking news.** A random event gives new script mid-show. The prompter op has
  20 s to type it.

## Random events (pool)
Studio fire alarm · the anchor's chair breaks · a pigeon in the studio · a camera cable
unplugged · a phone ringing on-air · a guest runs off · the prompter screen freezes ·
coffee spilled on the desk · a cleaner NPC walks through the shot · power flicker
· the station owner visits the control room

## Unlockable show variants (same set, different run-of-show)
- Morning show (a cooking segment, a yoga guest)
- Election night (numbers to type live, a big touchscreen map)
- Telethon (phones ringing everywhere, a donation meter)
- Late night with a studio audience (see brainstorm for more)

## Tape
Mostly just the broadcast output: the actual channel feed with lower thirds and
ticker. Blooper reel: control-room cam + floor cam.

## Level art needs
See [asset list](../04-art/asset-list.md#mode-were-live).

## Open questions
- Typed prompter vs. voice? Typing is funnier (typos) but excludes a player from
  voice. Maybe the prompter op can also talk on headset.
- How strict is the "read what's written" scoring? It needs speech-to-text, or is it
  honour-based? Probably **honour + the audience scores the Tape moments only**. Avoid
  STT in v1.
