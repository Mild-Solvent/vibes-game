# Scenario: STANDBY... GO! (one round of each show)

How a round should feel in the finished game. The last section says what exists today.

## We're Live! (Channel 6 Evening News)

**Setting.** A shabby TV studio: news desk on green tape, a weather green screen, a camera
on wheels, and behind the glass a control room with a big TAKE button. Yellow floor tape
marks where the on-air camera can see you. Cross it and you are on television.

**Roles (2-8).** Anchor (reads the teleprompter, out loud, exactly). Prompter op (types
that teleprompter live). Director (watches every camera feed, hits TAKE). 1-2 camera ops.
Weather presenter (green screen, cannot see the map). Floor manager (VT tapes, props,
chairs). At 2 players: anchor + one panicking everything-else, with NPC prompter.

**One round (3 minutes LIVE).**
- **-0:20 PREP.** Katka sits on the green tape. Marek, prompter op, tests the keyboard by
  typing "HELLO KATKA YOU SMELL". It goes straight to her prompter. Morale is set.
- **0:00 ● LIVE.** The tally light goes red. Director Tomas presses TAKE on CAM 1.
  CAM 1 is pointed at the ceiling. Ratings drip.
- **0:12** Katka: "Good evening. Tonight: local man finds cat." Marek types the next line
  as she reads, so she reads it as he types: "The mayor has been arse... ARRESTED."
  The bleep fires. Ratings go up. Failure is funnier than success.
- **0:40** Floor manager Peter runs VT_CAT_TREE to the deck. It is VT_CAT_TREE_FINAL_v2.
  Nobody knows which one is final. It is neither.
- **1:05** Weather. Zuzka stands on the green screen pointing confidently at Bratislava,
  which is actually her own knee. Peter, wearing a green hoodie, walks behind her and
  becomes a floating head. "CREW IN SHOT!" flashes red. He freezes, which does not help.
- **1:30** Camera op Jano pushes CAM 2 for a close-up, backs over the yellow tape and
  stars in his own shot. Ratings drain for every extra body in frame.
- **2:10** Katka leans out of the green box to grab the coffee. Nobody is at the desk.
  The channel cuts to "TECHNICAL DIFFICULTIES, PLEASE STAND BY". Dead air.
- **2:15** Breaking news. Marek has 20 seconds to type it. He types "BREAKING: Tomas cannot
  find the TAKE button". Tomas finds the TAKE button.
- **2:55** Sign-off. Katka reads "Goodnight, and good luck" correctly. Everyone is shocked.

**Win / lose.** RATINGS starts at 50%. One anchor at the desk, nobody else in frame: it
climbs. Dead air, crew in shot and wrong VTs drain it. WRAP gives stars and fake tweets.
You never "lose" mid-show: the broadcast just keeps going, worse.

**The Tape.** The actual Channel 6 feed with the lower third ("Local man finds cat. More
at eleven.") and the ticker. Highlights: the ARSESTED bleep, Peter's floating head, the
ceiling shot, the technical difficulties card. Blooper cut from the control-room cam:
Tomas screaming "TAKE! TAKE! WHICH ONE IS TAKE?"

## Places, Please! (opening night, Hamlet-ish)

**Setting.** A small municipal theatre. A raised stage behind a red proscenium, dark wings
with blue work lights, glowing tape marks, and a full house that can hear everything.

**Roles (2-8).** Actor on the yellow STAR. Stage manager (calls cues, whispers lines).
Deck crew (move the TREE, CASTLE_WALL and THRONE in blackouts). Booth op (lights, sound).
Fly crew and dresser at higher player counts. NPC actors fill gaps and walk to marks blindly.

**One round (3 scenes, 2 blackouts).**
- **0:00 Act 1: The Forest.** Lights up. Denis stands on the STAR as "the Prince". Lines:
  improvised. The skull is in his pocket for no reason.
- **0:18** He dries. Stage manager Ema whispers from the wings: "To be or not..." Too quiet.
  She tries again: "TO BE!" The front three rows hear it. A child says "to be" back.
- **0:25 BLACKOUT.** Twelve seconds. Glowing marks show where everything goes next. Two
  crew grab the tree, walk it in opposite directions, and argue in loud whispers the
  audience hears perfectly: "LEFT. MY LEFT. STAGE LEFT IS YOUR RIGHT."
- **0:37 Act 2: The Castle.** Lights snap up. The castle wall is on its mark. The tree is
  lying across the throne. Ondro is still on stage holding one branch. "CAUGHT IN THE
  LIGHT!" He freezes and becomes a second, sadder tree. Applause meter wobbles.
- **1:02 BLACKOUT.** The sword gets dropped. A loud clang in total darkness.
- **1:14 Act 3: The Throne Room.** Perfect change, all three pieces on marks. "Perfect scene
  change! Applause!" Nobody on the STAR though: the actor is still in the wing looking for
  the sword. "EMPTY STAGE!" He sprints on, out of breath, and dies dramatically. Fog
  machine goes off for the whole of the curtain call.

**Win / lose.** APPLAUSE starts at 50. Actor alone on the star in the light: it rises.
Empty stage, crew caught in light and wrong sets cost it. Each blackout is judged when the
lights come up: +6 per piece on its mark, -8 per piece off it.

**The Tape.** The audience view from row F: the forest that becomes a castle with a tree
in it, Ondro the frozen tree, the "TO BE!" whisper with the child echoing it, and the clang
in the dark. Balcony cam blooper: two silhouettes carrying a tree in a circle.

## Demo today vs still missing

**Demo today (games/tv-theatre)**
- One fixed on-air camera rendered to monitors, with LIVE tally, lower third, status tag.
- Ratings rules: one anchor on green tape climbs, dead air card, crew-in-shot drain.
- VT_CAT_TREE / FINAL_v2 / WEATHER tapes, cue sheet, coffee, chair as grabbable props
  (they do nothing yet).
- Theatre: 3 scenes and 2 blackouts, glow marks for the next layout, set judged on
  lights up, STAR and caught-in-light checks, audience-view monitors in the wings.
- Skull, sword, fog machine props; PREP / LIVE / WRAP loop; up to 8 players over LAN.

**Still missing**
- Teleprompter typed by a player, multiple cameras and the director's TAKE switcher.
- Weather green screen and chroma-key (and the green-hoodie gag).
- Any voice: proximity chat, live mics, whisper cues the audience hears, headset.
- VT playback, breaking news, random events, NPC actors and guests.
- Fly ropes, booth sound board, quick change, cue sheet timeline scoring.
- The Tape recording, highlights, clip export, WRAP stars and fake tweets.
