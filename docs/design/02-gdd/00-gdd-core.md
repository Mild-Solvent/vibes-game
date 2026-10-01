# GDD: Core (shared by every mode)

Every mode is a **Show**. Shows share the systems below. A mode doc only describes
what's different.

## Round structure
```
LOBBY (the studio / theatre building, hang out, pick the show)
  → PREP (2–3 min: read the run-of-show, grab props, test gear, dress the talent)
  → "STANDBY..." countdown
  → LIVE (8–12 min, clock never stops)
  → WRAP (the audience/ratings verdict)
  → THE TAPE (watch the show back, laugh, export a clip)
  → back to LOBBY, with money earned to spend on the next show
```

## Roles
Each show has **on-stage** and **off-stage** roles. Players pick in PREP and can
swap during LIVE by running around (physically, which is chaotic).
- **Talent** (on stage / on camera): the only person the audience "sees". Has to act calm.
- **Crew**: everything else. The audience never sees them, *unless they mess up*.
- If there are fewer players than roles, NPC talent / NPC extras fill in (dumb and
  exploitable, which is a gag in itself).

## The two worlds
- **Front** = what the audience sees and hears: the camera frame or the stage under lights.
- **Back** = everything else: dark, cluttered, cables, rigging, props.
- Anything that **crosses** from back to front is scored and becomes a Tape moment:
  a crew member walking into frame, a whisper caught by the mic, a dropped prop,
  a wrong backdrop.

## Voice (core mechanic)
- **Proximity chat** everywhere. It's the default and the main comedy engine.
- **Live mics**: objects like the anchor's lapel, a boom mic or the stage floor mics.
  Anything they pick up goes into the **broadcast mix**, so the audience hears it
  and it's on the Tape.
- **Headset channel**: crew-only radio (director ↔ crew). It's clear and global but
  one person talks at a time, push-to-talk, with a walkie-talkie feel. The talent
  gets an **earpiece**: they can hear the director but can't answer without talking
  on-air.
- **Whisper**: hold a key to talk more quietly. Shorter range, and live mics are less
  likely to pick it up.
- Optional later: **audience noise meter**. Loud swearing backstage is heard by the
  front rows.

## Run-of-show / cue sheet
Every show has a script of **cues** laid out on a timeline:
`00:45 CAM 2 on anchor · 01:10 roll VT "cat in tree" · 01:12 lower third: "Mayor"`
- Cues can be **hit** (on time), **late**, **wrong** (wrong tape, wrong backdrop) or **missed**.
- The cue sheet exists as **physical paper props**. One clipboard per show, so
  it can be dropped, lost, eaten or read out loud by the wrong person.
- **Random events** inject chaos on top of the script (see mode docs).

## Scoring: the audience
- **Ratings meter** (TV) / **Applause meter** (theatre): one shared bar, live on the monitors.
- It goes **up** on hit cues, good improv (talent keeps going), and "happy accidents"
  (some failures are *funny* and the audience loves them).
- It goes **down** on dead air or dead stage, visible crew, audible swearing, and
  wrong content.
- At WRAP: a star rating, a fake reviews/tweets screen (generated from Tape events),
  and money.
- Design rule: **failure should be funnier than success**. We want viewers screaming
  at a stream, not a perfect run.

## The Tape
- Records everything the **Front** saw and heard (camera feed / audience view
  + broadcast mix) plus a few backstage cameras for "blooper" cuts.
- Played back automatically after WRAP. Anyone can skip it.
- **Highlights**: auto-bookmarks on big events (crew in frame, fire, swear on air).
- **Export clip** (stretch goal, but high priority): a 30–60 s MP4/WebM saved to disk,
  ready for TikTok or Shorts.
  This is our free marketing.

## Money & meta (keep it light, retention is low anyway)
- Earnings buy: **new shows** (unlock order), cosmetic crew outfits, silly props
  and talent costumes, studio lobby decorations.
- No skill trees or grind. A new evening = new laughs, not new stats.

## Player interaction / physics
- Grab/carry/throw anything (R.E.P.O.-style physics hands).
- Ragdoll on trip / get hit. Cables on the floor are tripping hazards.
- Carrying big things together (set pieces, camera dolly) takes 2 people.

## Streamer features (plan from day 1)
- Big readable monitors in-world (the chat can read the cue sheet too).
- Optional **Twitch/YouTube chat integration** later: chat votes for random events
  ("the anchor's chair breaks"). Low effort, high return.
- Streamer-safe mode: the swear filter on the Tape replaces swears with a bleep sound.
  The bleep *is* the joke.

## Player count
2–6. Every show must be playable and funny at 2 (both run around crewing, NPC talent)
and at 6 (everybody has a job).
