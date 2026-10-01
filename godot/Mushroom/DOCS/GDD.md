# Mushroom Foraging: Game Design Document

Working title: **Mushroom Foraging** (a.k.a. "the mushroom game"). Engine: Godot 4.7, GL Compatibility.
Status: playable prototype, being expanded into the "friendslop update". Last updated 2026-10-01.

Sources this document is built from: the friendslop plan (`design/mushroom-friendslop-plan.md` in the
project files) with Father's amendments, `docs/scenarios/mushroom.md`, and the code in `godot/Mushroom/scripts/`.
Where the code and this document disagree, the code is what's built; this document is what we're aiming for.

Legend used in the tables and the roadmap: **BUILT** = in the game now, **PARTIAL** = in, but rough or
missing pieces, **PLANNED** = agreed, not built yet.

---

## 1. Pitch

> Four friends lost their jobs. Now they live in a tent in a Slovak forest, owe money to the wrong uncle,
> and the only thing they know how to do is pick mushrooms. Some mushrooms are dinner. Some are a trip.
> Some are a funeral. Somebody has to taste them.

A 1 to 4 player (up to 8 over LAN) co-op horror-comedy. Players forage weird mushrooms in a huge foggy
forest, taste-test them on each other, drive a terrible car to the village to sell them to Babka Hela,
and try to pay off Uncle Fero before the deadline. At night the forest gets truly dark and things come
out that hunt by **sound**, so the friend who screams gets everyone eaten.

### Pillars

1. **Friendslop chaos.** The fun comes from friends ruining things for each other: force-feeding,
   shoving, flipping the car, getting lost, describing a mushroom badly over voice. Systems exist to
   create stories, not to be optimised.
2. **Fear through sound.** Proximity voice and walkie-talkies are core. The Hag, the Nurse and the
   wolves hear you. Silence is safety; panic is loud. Lighting, fog and audio do the scaring, not gore.
3. **Poverty comedy.** Everything is cheap, broken and Slovak: a rusty slot machine found in a ruin,
   cheap wine, a lottery ticket, a loan shark uncle, graves with jokes on them.

### Target audience

- Groups of 2 to 4 friends on Discord who played Lethal Company, R.E.P.O., Peak, Content Warning,
  GONE Fishing or Schedule I and want the next 5-euro night of screaming.
- Streamers and clip makers: every session should produce a clip (the reel at the end of each day).
- Low-end PCs: GL Compatibility renderer, low-poly art, small download.
- Central European flavour as a hook (Slovak names, Babka, Škoda-ish car, Soviet sanatorium) that
  still reads instantly for anyone.

### Comparable games and what we take

| Game | We take |
|---|---|
| Lethal Company | a quota you can fail, monsters that hunt by sound, proximity voice terror |
| Peak | getting lost, needing friends to pull you out, ragdoll comedy |
| R.E.P.O. | physics hands, fragile loot that loses value when it breaks |
| Content Warning | the end-of-day highlights reel |
| Mage Arena / Lethal mods | monsters mimicking a friend's voice |
| Gang Beasts | shoving friends into things |
| Schedule I | shady side hustle (sell trippy mushrooms at night, police risk) |

---

## 2. Story and intro

**Setup.** Adam, Denis, Janka and Miro (default names; players type their own) all got fired from the
same factory on the same day. Rent is a dream. They pitch three tents in the forest outside the village,
park the car, and borrow money from Uncle Fero to get started. Uncle Fero does not wait.

**Intro (BUILT, text cards; PLANNED, a playable cold open).**

1. Black screen. A radio: "...the plant in Zvolen closes today, 400 workers..."
2. Card: *"Four friends. One car. Zero jobs."*
3. Cut to the junk camp at dawn. Uncle Fero's car pulls in, he leans out of the window: "Three days.
   150 euro. Don't make me come back." He drives off and splashes everyone with mud.
4. The field guide lies on the chest. Babka Hela's voice-over (as a letter): "Bring me mushrooms, boys.
   I'll tell you what they are. Don't eat the pretty ones."
5. Control returns. The tutorial is diegetic: signposts at camp ("JUNK CAMP / home sweet home",
   "HOUSE PLOT 300 €"), Babka's notes, and the first night teaching the rest the hard way.

**Endings.**
- **Debt paid in full** (all six quotas): Uncle Fero shakes hands and offers them a job. They refuse
  and go back to the forest. Credits over the reel of the whole run.
- **Missed quota:** Uncle Fero takes the car. Game over screen: the four of them walking home in the rain.
- **Everyone dead:** the witch is out of patience. Four graves get new epitaphs written from the run.

---

## 3. Core loop

```
DAWN at camp ──> FORAGE in the forest ──> TASTE / argue / force-feed
     ^                                          │
     │                                          v
 NIGHT recap <── survive the night <── DRIVE to the village, SELL to Babka, SHOP, CASINO
 (reel, Fero)                                   │
                                                v
                                  sick or dead friend? ──> WITCH ──> SCARY LOCATION
```

**Per day (one round):** pick up mushrooms (E), look at them (wheel / R), guess, carry them in a basket
or one at a time, drive to the village, sell to Babka Hela, buy batteries / medkits / junk, and get
home before night. Someone always gets lost.

**Per three days:** Uncle Fero collects. Pressure rises each cycle, which pushes people into riskier
mushrooms, the casino and the night dealer.

### Day and night cycle (BUILT, PARTIAL on dawn/dusk polish)

| Phase | Length | What happens |
|---|---|---|
| PREP (dawn) | 30 s | at camp; the sun comes up through fog; bodies, baskets and the slot machine stay where they were |
| LIVE: morning | ~0:00 to 5:00 | bright, light fog; Babka's stall and Jano's shop are open; villagers out |
| LIVE: afternoon | ~5:00 to 10:00 | golden light, fog thickens |
| LIVE: dusk | ~10:00 to 12:30 | orange then blue; the Hag wakes; villagers go home; lamps light up |
| LIVE: night | ~12:30 to 15:00 | near pitch black; wolves and boars charge; dark hallucinations start |
| WRAP (midnight recap) | 25 s | highlights reel, earnings, Uncle Fero's reminder or visit |

Total day: 15 minutes of LIVE (`forest.gd: live_duration() = 900`). The HUD shows "DAY n · m:ss until
midnight". Babka and the shopkeepers sleep at night; the casino stays open (of course).

---

## 4. Uncle Fero's debt quota (BUILT)

- Uncle Fero collects at the end of every 3rd day (`Team.QUOTA_EVERY = 3`).
- Quotas climb: **150 € → 350 € → 600 € → 1000 € → 1500 € → 2200 €** (`Team.QUOTAS`).
- Cash is shared by the team. Paying is automatic at the end of the collection day.
- Can't pay: the run is over (game over screen).
- The pause menu shows the current debt, days left and cash.
- PLANNED: Fero shows up in person at camp in his car, honks (which the Hag hears), and the payment is
  a little scene. If short, he takes something first (the car, the slot machine) and gives one extra
  day before game over, so a failed quota is a story, not just a screen.

---

## 5. Mushrooms

Every good mushroom has an evil twin. Names are **hidden** until Babka Hela identifies a species; until
then the HUD only describes what you see ("a big round-capped mushroom, brown"). Tasting no longer
reveals the name. Effects kick in **after a delay**, so you don't know who ate what until it's too late.

### The mushroom table

20 forest species plus 4 cure ingredients (`mushroom.gd: KINDS / FEATURES / TELLS / WEIGHTS`).
Look-alikes share a silhouette and almost the same colour; the **tell** is a detail you only see up
close with the inspect mode. Babka still names everything; once she has, the field guide lists the tell.

| Group | Species | Effect | Sells for | The tell (inspect it) | Spawn weight |
|---|---|---|---|---|---|
| Boletes | **Porcini** (hríb dubový) | food | 20 € | **pale** net on the stem, white pores | 8 |
| | **Bitter bolete** (hríb žlčník) | food, but worthless | 1 € | **dark** net on the stem, **pinkish** pores | 6 |
| | **Satan's bolete** | POISON | n/a | red stem with a red net, bruises **blue** | 5 |
| White caps | **Field mushroom** (pečiarka) | food | 12 € | **pink** gills, a ring, **no** cup at the base | 8 |
| | **Yellow stainer** | POISON | n/a | grey-white gills, bruises **yellow** where you hold it | 5 |
| | **Death cap** (muchotrávka zelená) | POISON | n/a | white gills, a ring **and a cup (volva)** at the base | 6 |
| Parasols | **Parasol** (bedľa vysoká) | food | 15 € | huge, snakeskin net on the stem, a ring | 7 |
| | **Shaggy parasol** (bedľa červenejúca) | food | 12 € | shorter, shaggy scales, bruises orange-red | 5 |
| | **Brown dapperling** (bedlička) | POISON | n/a | small, **no ring** | 4 |
| Orange funnels | **Chanterelle** (kuriatko) | food | 10 € | **ridges** running down the stem, not gills | 8 |
| | **False chanterelle** | TRIP | 12 € | real thin **gills**, more orange | 5 |
| | **Jack-o'-lantern** | POISON | n/a | real gills, an orange net on the stem | 4 |
| Moon caps (made up) | **Moon cap** | TRIP | 28 € | **white** gills under the cap | 4 |
| | **False moon cap** | POISON | n/a | **blue** gills under the cap | 4 |
| Odd ones | **Glowcap** | TRIP | 30 € | glows, pointy | 5 |
| | **Rainbow bolete** | STRONG (pass out, then trip) | 45 € | pink/green, glows | 3 |
| | **Golden chanterelle** | food, rare | 60 € | ridges, glows | 2 |
| | **Screaming puffball** | food | 18 € | a white ball | 5 |
| | **Devil's cigar** | POISON | n/a | tall, dark, a cup at the base | 4 |
| | **Witch's finger** | TRIP; the witch's fallback ingredient | witch only | dark finger, glows | 4 |
| Cure ingredients | **Mother's mould** / **Kobold cap** / **Bone morel** / **Drowned chanterelle** | CURE (give to the witch) | witch only | only in the sanatorium / mine / crypt / lake island at midnight | never random |

Effects kick in **later**: trips after 18 to 35 s, strong ones after 25 to 40 s, poison after 35 to 60 s
(then 240 s to get a medkit or the witch). 420 mushrooms are scattered at start
(`forest.gd: MUSHROOM_COUNT`); 40 of them are rare ones (golden chanterelles, rainbow boletes,
glowcaps, moon caps and their twins, witch's fingers) that only grow in the **fog hollows**.

**Handling (BUILT).** E picks up, Q throws, F tastes. **Inspect (BUILT):** hold the right mouse button
with a mushroom in hand: you stop, a fully detailed copy comes up in front of your face, the background
blurs. Mouse turns it (yaw/pitch), Q/E roll it, the wheel brings it from an extreme close-up (gills
fill the screen) to arm's length. Species that bruise change colour on the parts you've been holding
after a few seconds. Thrown too hard (over 6 m/s) three times, a mushroom breaks into bits.
PLANNED (R.E.P.O. rule): each hit lowers its sell price, so carrying the basket carefully matters.

**Selling (BUILT).** Babka Hela buys food and the fun ones (food, trip, strong), only species she has
named. You can sell from a basket or by putting a single mushroom on her counter. She refuses poison
and tells you what it was, loudly. PLANNED: the night dealer at the casino car park pays 3x for trip
mushrooms, but every sale raises police heat.

### Tasting and effects

| Status | Cause | What the player experiences | What friends see / hear |
|---|---|---|---|
| Tripping (40 s) | trip, witch's finger, the old slot's spore puff | wobbly controls, colour-shifting screen, friends look like zombies, fake Hags | the tripper's voice comes out pitch-warped (PLANNED) |
| Passed out (25 s) | rainbow bolete, or 3 trips within 120 s (overdose) | black screen, then a long trip | a floppy body you can drag, throw in the car |
| Poisoned (240 s) | Satan's bolete, death cap, devil's cigar | cramps text, HUD timer; at 0 you die | "Miro looks green. Really green." |
| Dead | poison, wolves, the Hag, the car, falling, drowning | ghost mode: float around, can still talk (to ghosts? open question) | your body stays, a prop |
| Stuck | bear trap, sucking mud | can't move | a friend has to press E on you |
| Vomit gag | drinking pond water | a delayed screen-wide vomit and a toast; no hunger meter | a vomit sound, everyone laughs |

Timers are separate per status, so one never cures another. **Fixed bug:** the pink pass-out mushroom
used to cure poison by accident; now only a medkit (H, 40 €) or the witch cures poison.

### Sanity in the dark (BUILT)

There are no hunger, thirst or firewood meters. The only "meter" is darkness:

- After 35 s in the dark with no light (`player.gd: DARK_SECONDS`) you start hearing whispers and see
  the Hag for a split second at the edge of the screen. Footsteps behind you. A friend calling your name.
- It escalates the longer you stay dark: fake mushrooms, a fake friend standing still between trees.
- **Turning on the flashlight clears it instantly.** So do the camp fire and village lamps.
- The design tension: light keeps you sane, but the Hag and the wolves can see torches.

### Flashlight and batteries (BUILT)

T toggles the torch. One battery lasts 150 s of light. Batteries are **shared by the team** (start with
2, 8 € each at Jano's shop). Whoever holds the light leads; turning it off hides you but loses you.

---

## 6. Threats

### The Hungry Hag (BUILT)

- Comes out at dusk. Hunts by **sound**: proximity voice, walkie-talkies, whistles, flares, the car
  engine and horn, the screaming puffball, dropped props. Hearing range up to 140 m for loud noises.
- Sees torches within 40 m.
- Wanders at 2.4 m/s, hunts at 6.4 m/s (faster than walking, a bit slower than a sprint).
- If she reaches you, **hold out a mushroom**: she snatches it and leaves you alone for 75 s. Empty
  hands: you're dinner.
- **Voice mimicry:** now and then she calls out in a friend's recorded voice, from where she is
  ("guys, over here"). The voice is real, the friend isn't.
- Stand still in the dark and shut up, and she passes by.

### Wolves (BUILT)

Asleep by day. At night 9 wolves roam near their dens, hear noise, see torches within 45 m and run
you down (7 m/s; a sprint at 7.5 m/s just about escapes). Two bites kill. They never come into camp
once the house is built, and never near the camp fire.

### Wild boars (BUILT)

10 boars. By day they snuffle around; at night they charge the nearest friend within 22 m. One hit
kills. Safe inside camp once the house is built.

### Police and the missing-friend timer (BUILT, PARTIAL on the visit scene)

- If a living friend is far from everyone else for too long, a **missing person** timer starts (120 s).
- Finding them (anyone within 20 m) calls it off.
- If it runs out, the police raid the camp: they confiscate the cash in hand and all mushrooms in
  baskets, and a cop keeps asking "where is your friend?"
- PLANNED: a police car with a siren drives the roads (the Hag hears it), the cop stays at camp until
  the friend is found, and the night dealer adds "heat" that can trigger a raid too.

### Dumb ways to die (BUILT)

Car run-over (over 7 m/s), car crash into a tree (over 17 m/s, kills everyone inside), falling (landing
over 17 m/s, the hill cliff), drowning (10 s under water), wolves, boars, the Hag, poison.

---

## 7. The witch and revive flow (BUILT for the flow, PARTIAL for locations)

1. Someone is poisoned (alive, timer running) or dead (a body on the ground).
2. Friends **carry the sick friend or the body** to the witch's hut in the swamp (south-west). Bodies
   are props: E to carry, throw them on the car's roof rack.
3. Talk to the cauldron. Empty-handed: *"Bring me the guy, dearie. I can't cure what I can't see."*
4. With the patient within 10 m, she names an ingredient and a place: *"For Miro I need a Bone morel,
   from the saint's coffin in the chapel crypt. Hurry, dearie."*
5. Go to the scary location, get the ingredient, bring it back, drop it in the cauldron (or in a basket
   right next to it).
6. She cackles. The poisoned friend is cured; the dead friend stands up.

The poisoned friend's 240 s timer keeps ticking the whole time, so usually the plan becomes "carry Miro
there, he dies on the way, now we carry his body". Dead friends wait as ghosts (no time limit), so the
witch is the only way back. If no location is built yet, she asks for a Witch's finger from the forest.

PLANNED: the medkit only buys time on deep poison (halves the timer) rather than curing everything, so
the witch run happens more often.

---

## 8. Scary cure locations

Each is a small, dense "facility" in the Lethal Company sense: one threat, one way to mess up, one
moment that makes friends scream at each other. All share `scripts/locations/location.gd` (merged
static geometry per 14 m chunk, host-run monsters, ingredients are ordinary mushroom props).

### 8.1 Sanatórium Hôrka (BUILT, first pass)

Abandoned Soviet sanatorium on a hill north-east of the village road.
**Ingredient:** Mother's mould, in the basement morgue. **Threat:** the Nurse, blind, hunts by sound.

| Beat | What happens |
|---|---|
| 1. Arrival | The road ends at a rusty gate. The building is lit only by the moon. A PA crackles: "Patients, return to your rooms." |
| 2. Lobby | Wheelchairs, a reception desk, a map of the floors on the wall. Every tray, bucket and gurney is a **loud prop**: bump it and it clatters. |
| 3. Corridors | Long, dark, with doors. Footsteps here are reported to Hearing (walk 5 m, sprint 14 m). Wheelchairs roll on their own. One friend has the only working torch; everyone whispers. |
| 4. The Nurse | She shuffles her rounds at 1.3 m/s. Anything she hears, she runs to at 5.4 m/s (6.1 at night). Freeze and stay quiet and she passes right by your face. Touch = death. |
| 5. Morgue | Down the stairs, drawers, a glowing patch of mould on a slab. |
| 6. Messing up | Lifting the mould trips the alarm: lights flash, a siren wails (every hunter hears it), the main doors lock. |
| 7. Escape | Find the laundry chute (one person at a time, slides you to the yard) or the broken window on the first floor (jump, risk a fall). |
| 8. Friendslop moment | "Don't. Move." while the Nurse stands between two friends and one of them has the giggles. |

### 8.2 Old mine Hodruša (PLANNED)

On the slope west of camp. **Ingredient:** Kobold caps, glowing, deep in the shafts.
**Threat:** cave-ins and the Miner, a ghost who steals your lamp.

| Beat | What happens |
|---|---|
| 1. Entrance | A wooden headframe, a sign "VSTUP ZAKÁZANÝ". Rails lead into the dark. |
| 2. Mine cart | A cart ride down the main shaft. Whoever pulls the lever is the driver; braking is optional. Crashes ragdoll everyone. |
| 3. Ladders and crawlspaces | Narrow crawlspaces fit one player, so the group has to split up. Walkies crackle and cut out underground. |
| 4. The Miner | A cold breeze, then your lamp is gone. He takes lights, not lives, but in the dark the sanity effects start fast. |
| 5. Cave-ins | Shouting or explosions shake the ceiling; rocks fall and split the group. |
| 6. Messing up | A **gas pocket** in one tunnel: light a flare in it and it explodes, ragdolling everyone and sealing the tunnel. |
| 7. Kobold caps | Glowing on the wall of the deepest gallery. |
| 8. Friendslop moment | Someone is stuck behind rubble and narrates in panic over the walkie while the others dig. |

### 8.3 Chapel crypt (PLANNED)

Under the old chapel north of the lake. **Ingredient:** the Bone morel on a saint's coffin.
**Threat:** skeletons that only move while nobody is looking at them.

| Beat | What happens |
|---|---|
| 1. Chapel | A small chapel, candles, an organ. Touch the organ and it plays (very loud). |
| 2. Stairs down | Candles blow out as you pass. The crypt is small and claustrophobic. |
| 3. The coffin | The Bone morel grows on the lid. Lifting it wakes the skeletons in the wall niches. |
| 4. Skeletons | Weeping Angels / SCP-173 rules: they move only when no player's camera faces them. Someone has to keep watching. |
| 5. Messing up | The floor gives way if more than two people stand on the cracked middle slab. Everyone below ends up in the ossuary. |
| 6. Friendslop moment | "Don't blink, I'm grabbing it, DON'T LOOK AWAY." Then someone checks the walkie. |

### 8.4 Lake island at midnight (PLANNED, optional)

The island in the middle of the lake. **Ingredient:** a Drowned chanterelle that only grows there at night.

| Beat | What happens |
|---|---|
| 1. The boat | A leaky rowboat at the shore. Two people must row in sync (alternating keys) or it spins. |
| 2. Crossing | Fog on the water. Something underwater bumps the boat. |
| 3. Island | A dead tree, a shrine, the teal chanterelle growing in the roots. It only exists 23:00 to 00:00. |
| 4. Messing up | The boat sinks if you load it with too much (three people plus the basket). Swim 10 s or drown. |
| 5. Friendslop moment | Rowing out of sync, in circles, while the thing in the water bumps again. |

---

## 9. Friend chaos mechanics

| Mechanic | How it works | Status |
|---|---|---|
| **Force-feed tug-of-war** | Hold a mushroom, look at a friend, spam T. They spam T to keep their mouth shut. A left/right meter swings towards whoever mashes faster (first to 14, max 7 s). Feeder wins: they eat it. Victim wins: the mushroom flies off. Only the two players see the meter. | BUILT |
| **Ragdoll bodies** | Passed-out and dead friends become floppy, heavy props. Carry them (E), throw them in the car's roof rack, drop them in the cauldron's range. | BUILT (body prop) / PARTIAL (true ragdoll physics) |
| **Shoving** | Q with empty hands shoves the friend you look at. Near the cliff or the lake it's a prank. | BUILT (push) / PLANNED (ragdoll fall) |
| **Field guide (split knowledge)** | One physical book. Only whoever holds it can read the journal (J) of what Babka has named. Everyone else has to describe mushrooms over voice. | BUILT |
| **Pull a friend out** | Bear traps and mud: you're stuck until a friend presses E on you. | BUILT |
| **Lift the car** | Take a corner too fast and the car flips. Two different players have to press E on it within a couple of seconds to heave it back. | BUILT |
| **Tripping social chaos** | The tripper sees friends as zombies and fake Hags, so nobody trusts what they report. Their voice comes out warped for everyone. | BUILT (visuals) / PLANNED (voice warp) |
| **Highlights reel** | At midnight the WRAP screen shows the day's moments: deaths, pass-outs, screams, with a snapshot of that player's screen. | BUILT (first pass) |
| **Flares and whistles** | Lost? Fire a flare (G) everyone sees, or blow a whistle (B). The Hag hears both. | BUILT |

---

## 10. Car and map

### The car (BUILT)

A Kenney SUV, four seats. E to get in (first in drives) or out. The driver's PC simulates it and
everyone else follows. Hit someone over 7 m/s and they die; hit a tree over 17 m/s and everyone inside
does. The roof rack carries baskets and bodies. **Flips** in fast corners and needs two players to lift it.
PLANNED: a working trunk, a horn (loud), headlights that use no batteries (a lighthouse at camp).

### The map (BUILT)

1100 × 1100 m heightfield from a fixed seed (every peer builds the same world), mountains around the
edge, dirt roads for the car and narrow footpaths that fork and loop on purpose. On foot the village is
about 4 minutes away, so **the car is required** to get anywhere in a day.

| Zone | Where (x, z from camp) | What's there |
|---|---|---|
| **Junk camp** (home) | (0, 0) | 3 tents, camp fire, bedrolls, chest with the field guide, workbench with the basket, the car, the HOUSE PLOT (300 €: animals stop coming into camp) |
| **Village** | (380, 110), east by road | fountain square, houses with night lights, **Babka Hela's stall** (identify and sell), **Jano's shop**, villagers who go home at night |
| **Casino Royale Zvolen** | (420, -110), off the village road | 4 slot machines (20 € a spin), vending machine, bouncer, pink neon |
| **Witch's hut** | (-360, -300), south-west swamp, footpath only | crypt-like hut, cauldron, crooked pines, graves with funny epitaphs |
| **Ruin** (hidden) | (-140, 290), north-west, on a footpath | ruin columns, and the **old slot machine** you can carry home |
| **Big hill and cliff** | (-250, 0), west | 30 m hill, steep east side: shoving and falling deaths |
| **Lake and island** | (150, -230), south | 62 m lake, 13 m island in the middle, lily pads, a canoe |
| **Sanatórium Hôrka** | (260, 370), north-east by road | scary location 1 |
| **Mine Hodruša** | (-410, 170), west by road | scary location 2 (planned) |
| **Chapel crypt** | (130, -400), south by road | scary location 3 (planned) |
| **Deep forest** | everywhere else | dense pines and leafy trees, ferns, logs, rocks, 70 bear traps and mud patches, critters (deer, bunnies, foxes flee from you) |

There is **no minimap**. A compass (25 €) adds a heading strip to the HUD. Signposts at junctions are
fixed, two-sided signs.

### Village, shop and casino (BUILT)

**Babka Hela** is an old granny at the red stall. She names mushrooms you bring her (that's the only way
names are revealed) and buys the sellable ones. She sleeps at night.

**Jano's shop** (green stall):

| Item | Price | Use |
|---|---|---|
| Medkit | 40 € | H: cures poison and wakes the passed-out (on the friend you look at, else yourself) |
| Battery | 8 € | shared torch power, 150 s each |
| Basket | 15 € | a spare basket (4 hidden in the shop) |
| Compass | 25 € | heading strip on the HUD |
| Flare | 12 € | G: everyone sees it, everything hears it |
| Whistle | 6 € | B: loud, the Hag hears it |
| Walkie-talkie | 30 € | hold V to talk to everyone with a walkie, any distance |
| Cheap wine | 4 € | useless, funny (drunk wobble) |
| Rubber duck | 3 € | useless, squeaks |
| Lottery ticket | 2 € | tiny chance of real money |
| House | 300 € | built on the camp plot; wolves and boars stay out |

**Casino slots** (20 €): 2% jackpot 500 €, 8% +100 €, 20% +40 €, otherwise nothing.

**The old slot machine** (hidden in the ruin): rusted shut until you carry it home (within 18 m of
camp). Then F spins it for 5 €: 25% battery, 15% medkit, 12% +40 €, 2% +250 €, 10% a spore cloud
in your face (trip), 36% a moth.

---

## 11. Voice and walkie-talkies (BUILT, core)

- **Proximity voice:** everyone hears you within ~28 to 30 m, positional, from your head. Volume is
  turned into Noise for the monsters: whisper ~4 m, talking ~15 m, shouting ~35 m.
- **Walkie-talkies** (30 €): hold V to talk to everyone holding a walkie. Clear up to 150 m, crackly
  to 350 m, gone past 500 m. The Hag hears the **receiving** walkie too, so calling a friend who is
  hiding can get them killed.
- **M** mutes your mic. Push-to-talk and an open mic are both options in Settings.
- **Mimicry:** the Hag replays snippets of friends' real voices.
- Built in GDScript: 16 kHz mono, noise-gated, 8-bit mu-law, 40 ms packets, ~16 KB/s per talker.
- PLANNED: trippers' voices pitch-warped for everyone; walkies cut out underground in the mine.

---

## 12. Menus and UI

**Main menu (BUILT):** Host, Join (address and port, shows this PC's LAN / Tailscale / Radmin / Hamachi
addresses), Lobby (player cards with READY, host starts), Settings, How to play (paged), Credits, Quit.

**Settings (BUILT):** volumes (master, music, SFX, voice), mic device and mic test, push-to-talk,
mouse sensitivity, invert Y, FOV, fullscreen, vsync, graphics quality.

**Pause menu (BUILT):** the game keeps running (it's multiplayer). Resume, Settings, How to play,
current day / cash / debt and quota, the journal, Leave (back to menu), Quit.

**HUD (BUILT):** top: day and "m:ss until midnight"; top-right: day and cash; bottom-left: medkits,
batteries, torch charge; bottom-right: field journal hint; centre: crosshair and what it's on
("a big round-capped mushroom, brown"); toasts; status (tripping / poisoned timer / stuck); the
force-feed meter; compass strip if owned; mic and walkie icons.

**WRAP screen:** the highlights reel grid, earnings for the day, and Fero's countdown.

---

## 13. Controls (BUILT)

| Key | Action |
|---|---|
| W A S D | move |
| Shift | sprint |
| Space | jump / swim up / brake in the car |
| E | grab, use, get in the car, lift the car, free a stuck friend |
| Q | throw what you hold / shove someone (empty hands) |
| F | taste what you hold / use |
| R / mouse wheel | turn the held item |
| H | medkit (on the friend you look at, else yourself) |
| T | flashlight / force-feed a friend (spam it) |
| G | use a pocket item: flare, wine, duck, lottery ticket |
| B | whistle |
| V (hold) | walkie-talkie |
| M | mute / unmute mic |
| J / Tab | field journal (while holding the field guide) |
| Esc | pause menu |

Gamepad: PLANNED.

---

## 14. Multiplayer model (BUILT)

- ENet, port 7777, up to 8 players (designed for 4). LAN, or over Tailscale / Radmin / Hamachi.
  PLANNED: Steam lobbies once there's a Steam build.
- **Host (peer 1) is authoritative** for spawning, props, mushrooms, monsters, the team state
  (`Team` autoload: cash, debt, statuses, inventory), the day cycle (`GameDirector`) and traps.
- **Each player owns its own movement** (client-authoritative), synced by MultiplayerSynchronizer.
- The **car** belongs to whoever drives it; with nobody at the wheel, the host simulates it.
- Props are host-simulated; clients see frozen copies that follow the host's transform.
- Clients ask the host with `any_peer` + `call_local` RPCs (`request_*`).
- The world is built identically on every peer from a fixed seed, so node paths always match.
- Voice is unreliable-ordered RPCs on their own channel, relayed by the host, which also turns voice
  loudness into Noise for the monsters.
- Late join: PLANNED (currently join in the lobby before the day starts).

---

## 15. Open questions

1. Can the dead talk to the living? (Lethal Company says no; it's funnier if ghosts can only whisper
   to trippers.)
2. Should the medkit fully cure poison, or only halve the timer so the witch matters more?
3. Night dealer (Schedule I hustle): in or out? It adds money but also another system.
4. How many days is a full run? Six quotas is about 18 days, roughly 5 hours. Too long for a session?
   Option: save at camp between days.
5. Solo play: allowed but not balanced for. Do we scale quotas by player count?
6. Mushroom spawn: do they regrow every day, or does the forest run out near camp (forcing longer drives)?
7. The highlights reel: snapshots only, or a short recorded clip (costly on potato PCs)?
8. Steam release, price point, and whether this ships alone or inside the STANDBY... GO! umbrella.

---

## 16. Roadmap

### Built (as of 2026-10-01)

- Godot 4.7 project, GL Compatibility, menu with host / join / lobby / settings / how to play / pause
- 1100 m map: camp, village, casino, witch, ruin, hill with cliff, lake with island, roads and footpaths,
  dense forest, critters that flee
- 16 mushroom species, look-alikes, hidden names, Babka identifies, delayed effects, breaking
- Statuses: trip, pass-out, poison, dead (ghost), stuck; overdose; pond vomit gag; dark hallucinations
- Basket, spare baskets, field guide, Jano's shop, casino, old slot machine, house plot
- Car with seats, roof rack, run-over and crash deaths, flipping and two-player lift
- Uncle Fero's quota, police missing-friend timer and raid
- The Hag (sound hunting, torch sight, mushroom bribe, voice mimicry), wolves, boars, traps
- Proximity voice, walkie-talkies, mic mute; sound effects and day/dusk/night ambience
- Force-feed tug-of-war, shoving, carrying bodies, witch revive flow, highlights reel (first pass)
- Sanatórium Hôrka with the Nurse

### Planned, in order

1. **Bug pass** from the playtest list (slow spots in hollows, eaten mushroom stuck in the air, foliage
   popping, basket not accepting mushrooms, dawn/dusk polish).
2. **Fero in person** (scene at camp), and failed-quota grace day.
3. **True ragdolls** for bodies and shoves, cliff and lake pranks.
4. **Trip voice warp**, walkie dropouts underground.
5. **Mine Hodruša** with the cart, the Miner and the gas pocket.
6. **Chapel crypt** with the don't-look skeletons.
7. **Lake island** with the two-person rowboat.
8. Night dealer and police heat.
9. Playable intro cold open, endings.
10. Steam build, gamepad, late join, save between days.
