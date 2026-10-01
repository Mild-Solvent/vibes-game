# Mushroom Foraging: Art Design Document

Companion to [GDD.md](GDD.md). This covers how the game looks and sounds, what's already in, and what
the artist could design. Last updated 2026-10-01.

The short version: **chunky low-poly toy world by day, a real horror game by night.** The models stay
cute and cheap; light, fog and sound do the scaring.

---

## 1. Visual style

- **Chunky low-poly, flat-shaded**, matching the Kenney kits already in the game (Nature Kit, Car Kit,
  Mini Characters, Graveyard Kit...) and the Quaternius / Poly Pizza style. Big readable shapes, few
  polygons, no texture detail beyond simple colour atlases.
- **Toy proportions.** Characters are short and stubby (Kenney Mini Characters), trees are slightly too
  big, mushrooms are slightly too big. The world looks like a diorama you could pick up.
- **Readability over realism.** Every mushroom must be identifiable at 3 m by **shape + cap colour +
  stem colour + glow**, because players describe them to each other over voice. Look-alike pairs differ
  in exactly one or two of those, on purpose (see GDD §5).
- **Day is cosy, night is hostile.** The same diorama under two lighting setups. Daytime should feel
  like a children's book about the forest; night should feel like Lethal Company.
- **Central European, not generic fantasy.** Spruce and pine, birch at the edges, a fountain square,
  pastel village houses, a Soviet concrete sanatorium, a wooden chapel, plastic garden chairs.
- **Renderer limits:** GL Compatibility (potato PCs). No SSAO, SSR or volumetric fog; use the
  environment's depth fog, a few omni lights, vertex-coloured or single-atlas materials, and keep
  materials matte (`model_fit.gd` strips metallic from Kenney imports).

### What not to do

- No realistic PBR textures next to flat-shaded models.
- No gore. Death is a floppy body and a funny grave.
- No pure black anywhere the player needs to read something (UI text, mushrooms): night still has a
  deep blue floor colour.

---

## 2. Palette

Hex values are targets for the sky, fog, sun and ambient settings in `forest.gd`, and the reference
for any new art.

### Day (morning to afternoon)

| Role | Hex | Notes |
|---|---|---|
| Sky top | `#8FB3CF` | washed-out blue, a bit grey (matches the current build) |
| Sky horizon / fog | `#C9D6D8` | light, low-contrast fog that hides the far forest |
| Sun | `#FFF4DC` | warm white |
| Grass | `#7FC46A` | Kenney green |
| Dirt road / camp | `#A8784A` | |
| Spruce | `#3E8F5E` | |
| Tent canvas | `#F2A3A0` | faded pink, poverty chic |

### Dusk

| Role | Hex | Notes |
|---|---|---|
| Sky top | `#3B3F6B` | |
| Horizon glow | `#F08A4B` | short, the "go home now" signal |
| Fog | `#8E7A86` | mauve, thicker than day |
| Sun | `#FF9B5E` | low and orange |
| Lamp light | `#FFCC73` | village lanterns switching on |
| Neon (casino) | `#FF4FD8` | the brightest thing on the map at dusk |

### Night

| Role | Hex | Notes |
|---|---|---|
| Sky | `#05070D` | near black |
| Fog | `#0B1018` | very thick, eats the torch at ~25 m |
| Ambient floor | `#141B2A` | never pure black: shapes stay barely readable |
| Moonlight | `#6F86B8` | weak, from high up, only on open ground |
| Torch | `#FFE7B0` | warm cone, the only "safe" colour |
| Camp fire | `#FF9A40` | flickering, a safe zone |
| Glow mushrooms | `#3FF2FF` glowcap, `#E63DD9` rainbow, `#FFE24D` golden, `#C8FF4D` kobold | they glow so they can be found at night (and so people go out at night) |

### Trip states

| State | Colours | Notes |
|---|---|---|
| Tripping | hue cycling through `#FF5FD2`, `#5FFFB0`, `#FFE45F`, `#6F7BFF` | slow hue rotation + wobble in `hud.gd`'s TRIP_SHADER |
| Strong trip (rainbow bolete) | saturated rainbow, high contrast, then fade to black | "you see the face of God, then the ground" |
| Passed out | `#000000` with a `#2A0F2E` vignette pulse | |
| Poisoned | desaturate to `#7A8C5A` sickly green, vignette pulsing with the heartbeat | gets stronger as the timer runs out |
| Dark hallucination | no tint; a cold `#9FB0C8` edge vignette and things that shouldn't be there | the point is that it looks *real* |
| Dead (ghost) | everything desaturated to `#B8C4C8`, slight bloom | |

---

## 3. Lighting and fog

- **One DirectionalLight (sun/moon)** whose colour, energy and angle follow the day (GDD §3). Proper
  **dawn and dusk** transitions over ~2 minutes each, not a jump from black to day.
- **Depth fog** is the main tool. Day: start ~60 m, light. Dusk: ~35 m, mauve. Night: ~12 m start,
  fully opaque by ~40 m. The forest must swallow people at night so "where's Adam?" happens.
- **Practical lights carry the night:** torch cones (SpotLight, warm), the camp fire (flickering
  OmniLight), village lanterns and window lights (switch on at dusk), casino neon, car headlights.
  Keep it to a handful of lights near the player for the Compatibility renderer.
- **Light is a gameplay signal.** Warm light = safe from sanity effects, but visible to the Hag and the
  wolves. The only safe *and* hidden light is the camp fire inside the house plot.
- **Interiors (scary locations):** no ambient at all inside. Light comes from the torch, emergency
  lights (red), flickering fluorescent tubes (sanatorium), the glow of the cure ingredient.

---

## 4. Characters

All characters use the **Kenney Mini Characters** proportions (or match them): ~1.75 m in-game, big
head, simple faces, idle / walk / sprint / sit animations.

| Character | Look | Current asset | Notes for the artist |
|---|---|---|---|
| **The four friends** | jobless guys and girls in tracksuits, hoodies, a reflective vest from the old job, rubber boots | Kenney Mini Characters (8 looks) | each needs a readable silhouette + a colour that shows in the dark (the name tag helps). Hats would be great. |
| **Babka Hela** | a real old granny: headscarf (šatka), cardigan, apron, glasses, hunched, a cane | Poly Pizza `grandmother.glb` | must read as OLD at a glance (playtest note: the first model looked young) |
| **The witch** | old woman in rags, long nose, crooked staff, hut in the swamp | Poly Pizza `witch.glb` (100 Avatars) | creepy but friendly ("dearie"). Not the farmer model with a cauldron. |
| **The Hungry Hag** | tall, too thin, long arms, grey skin, rag dress, mouth too wide | Poly Pizza `hag.glb` | must be different from the witch at a glance, even in the dark: taller, hunched forward, pale. |
| **The Nurse** | blind, bandaged eyes, pale uniform, Soviet nurse cap | mini-character with a ghost material | silhouette of a nurse cap is the tell |
| **Uncle Fero** | gold chain, leather jacket, moustache, sunglasses at night, cigarette | not yet | always next to his car; small man, big presence |
| **Police** | Slovak police (green/yellow), moustache, notebook | not yet | asks "where is your friend?" forever |
| **Villagers** | locals: a man with a moustache and a hat, women with shopping bags, Jano the shopkeeper in an apron | Kenney Mini Characters | they go home at night |
| **The Miner (ghost)** | translucent miner, helmet lamp off | planned | |
| **Skeletons (crypt)** | stubby skeletons that freeze in poses | planned (Kenney Graveyard has a skeleton) | poses should be funny when you look back |
| **Animals** | deer, bunnies, foxes (flee), boars (charge), wolves (hunt) | Kenney Cube Pets, Poly Pizza `wolf.glb` | wolves need glowing eyes at night |

---

## 5. Environments per zone

| Zone | Mood | Key props and look |
|---|---|---|
| **Junk camp** | poverty cosy | three faded pink tents, a camp fire, bedrolls, a chest, a workbench, barrels, a "JUNK CAMP / home sweet home" signpost, the car, the house plot (a suburban house appears when bought). Add: tarps, a washing line, plastic chairs, a satellite dish on a stick. |
| **Deep forest** | alive by day, hostile by night | spruce and pine (several sizes), leafy trees at the edges, birch, ferns, bushes, logs on the ground, stumps, rocks, mossy patches, footpaths worn into the grass, bear traps and mud. Density goes up the further from roads. |
| **Village** | postcard Slovak | fountain square, pastel houses with warm windows at night, lanterns, Babka's red stall, Jano's green stall, a cart, a bus stop with no bus. |
| **Casino Royale Zvolen** | sad glitter | a concrete box with a pink neon sign, an awning, slot machines, a vending machine, a bouncer, a car park with one Mercedes (Fero's). |
| **Witch's hut** | swampy, crooked | crooked pines, mist low to the ground, gravestones with funny epitaphs, candles, the cauldron with green steam. |
| **Ruin** | forgotten | a few columns, rubble, the old slot machine half-buried in leaves. |
| **Hill and cliff** | open, windy | rocky slope, a view over the forest (the only place you can see far), a cliff on the east side. |
| **Lake and island** | still, wrong | dark water, lily pads, reeds, a canoe/rowboat, the island with one dead tree and a little roadside shrine. |
| **Sanatórium Hôrka** | Soviet decay | grey concrete, green-tiled corridors, wheelchairs, gurneys, steel trays, PA speakers, a mosaic of happy workers in the lobby, the morgue with drawers. |
| **Mine Hodruša** | claustrophobic | timber supports, rails, a cart, ladders, wet rock, a headframe outside. |
| **Chapel crypt** | small, holy, wrong | wooden village chapel, organ, candles, stone stairs, wall niches with skeletons, the saint's coffin. |

---

## 6. Props

**Gameplay props (must read instantly):** mushrooms (16 species, built in code from cap/stem/glow
shapes: dome, flat, tall, ball, finger), the basket, the field guide (a fat green book), the medkit
(red cross), batteries, flashlight, walkie-talkie, flare, whistle, compass, the old slot machine,
bodies, bear traps, mud patches.

**Joke props (cheap and Slovak):** a bottle of cheap wine, a rubber duck, lottery tickets, a garden
gnome, a Kofola bottle, a plastic chair, a tracksuit on a washing line, a car tyre, a Škoda hubcap.

**Signs:** fixed two-sided wooden signposts at junctions (not billboards), the grave epitaphs, the casino
neon, hand-painted price signs on stalls.

---

## 7. UI style: the Slovak village look

- **Feel:** a village noticeboard and a grandma's kitchen. Paper notes pinned on wood, hand-written
  prices, embroidered folk patterns (čičmany geometric motifs) as borders.
- **Colours:** dark wood `#2B1E16`, paper `#F3E9D2`, folk red `#C8312B`, forest green `#2F5D3A`,
  warning yellow `#F2C230`. The menu is lit by a warm lamp, the in-game HUD is minimal white text with a
  soft dark shadow.
- **Fonts:** a chunky rounded sans for the HUD (readable at 720p), a hand-written font for Babka's
  notes and the journal, a stencil font for police and Fero. Must support Slovak diacritics (á, ä, č,
  ď, é, í, ľ, ĺ, ň, ó, ô, ŕ, š, ť, ú, ý, ž).
- **HUD:** almost nothing on screen. Day and time top centre, cash top right, items bottom left, the
  journal hint bottom right. No minimap ever. Status effects show on the screen itself (shaders) more
  than in text.
- **Icons:** simple flat icons (already generated in `ui/icons.gd`): medkit, battery, torch, mic,
  walkie, compass.
- **Menus:** main menu over a slow camera at the camp fire at dusk; lobby as player cards; pause menu
  as a notebook page with the debt written in red.

---

## 8. VFX

| Effect | Look |
|---|---|
| **Trip** | screen wobble and hue cycling (TRIP_SHADER), trees "breathing" (vertex sway), friends swapped for zombie models, fake Hags at the torch edge, mushrooms that aren't there. |
| **Strong trip** | kaleidoscope + rainbow, then fade to black (pass out). |
| **Poison** | green desaturation, pulsing vignette synced to a heartbeat sound, sweat drops on screen, slower stride. |
| **Vomit** | delayed: a green-brown splash across the screen and a puddle decal at your feet. Pure comedy. |
| **Mushroom breaking** | a puff of cap-coloured chunks and spores. |
| **Spore cloud** (old slot) | a pink puff in your face. |
| **Dark hallucination** | subtle: a figure between trees for one frame, a second torch beam that isn't anyone's, whispers. |
| **Flare** | red light that lights a huge area, smoke trail. |
| **Witch cure** | green steam from the cauldron, a cackle, the body stands up. |
| **Ghost** | translucent, desaturated, floats. |
| **Car flip / crash** | dust, a hubcap rolls away. |

---

## 9. Audio direction (sound is core to fear)

Sound is a mechanic, not decoration: **if you can hear it, it might be able to hear you.**

- **Ambience (BUILT):** three loops crossfaded by time of day: day birds and wind, dusk crickets,
  night silence with a far-off howl, an owl, a branch snapping (random one-shots around you, not heard
  by monsters).
- **Voice is the main sound.** Proximity voice is positional from each friend's head; walkies are dry,
  band-limited and crackly. Silence must feel heavy at night: no music in the forest after dusk.
- **Threat tells:** the Hag breathes (positional loop) and hums; wolves pant and howl before they run;
  the Nurse's shoes squeak; the Miner is a cold wind. Players should learn to *hear* danger before they
  see it.
- **Mimicry:** the Hag plays a real friend's voice clip with a little extra reverb. It should be almost
  right.
- **Comedy sounds:** the screaming puffball, the rubber duck, the vomit, the slot machine jingle, the
  car horn, Babka's "Ježišmária!"
- **Music:** only in menus, the casino (cheesy synth), the village by day (accordion/folk loop), and the
  WRAP reel. Never in the forest.
- **Sources:** Kenney CC0 audio packs plus synthesized sounds (`assets/sfx/tools/gen_sfx.py`). See
  `assets/sfx/CREDITS-sfx.md`.

---

## 10. Asset list

All current art is free. Kenney is CC0. Each pack folder keeps its licence file.

| Asset | Source | Licence | Used for | Status |
|---|---|---|---|---|
| Mini Characters | [Kenney](https://kenney.nl/assets/mini-characters) | CC0 | the friends, villagers, Jano | in game |
| Mini Characters extra (wheelchair) | Kenney | CC0 | sanatorium | in game |
| Nature Kit | [Kenney](https://kenney.nl/assets/nature-kit) | CC0 | trees, bushes, ferns, rocks, logs, lily pads, canoe, ruin, tents | in game |
| Car Kit (SUV) | [Kenney](https://kenney.nl/assets/car-kit) | CC0 | the car | in game |
| Survival Kit | [Kenney](https://kenney.nl/assets/survival-kit) | CC0 | camp fire, bedrolls, chest, workbench, barrels | in game |
| City Kit (Suburban) | [Kenney](https://kenney.nl/assets/city-kit-suburban) | CC0 | village houses, the camp house | in game |
| City Kit (Commercial) | [Kenney](https://kenney.nl/assets/city-kit-commercial) | CC0 | casino building | in game |
| Fantasy Town Kit | [Kenney](https://kenney.nl/assets/fantasy-town-kit) | CC0 | fountain, stalls, cart, lanterns | in game |
| Mini Arcade | [Kenney](https://kenney.nl/assets/mini-arcade) | CC0 | slot machines, vending machine, bouncer | in game |
| Mini Market | [Kenney](https://kenney.nl/assets/mini-market) | CC0 | the basket | in game |
| Graveyard Kit | [Kenney](https://kenney.nl/assets/graveyard-kit) | CC0 | crypt, gravestones, crooked pines, zombie (trip monster) | in game |
| Cube Pets | [Kenney](https://kenney.nl/assets/cube-pets) | CC0 | boars, deer, bunnies, foxes | in game |
| Furniture Kit | [Kenney](https://kenney.nl/assets/furniture-kit) | CC0 | sanatorium interiors | in game (not yet in CREDITS.md) |
| grandmother.glb, witch.glb, hag.glb, wolf.glb | [Poly Pizza](https://poly.pizza) | **to verify** (Poly Pizza models are CC0 or CC-BY per model) | Babka Hela, the witch, the Hag, wolves | in game, **missing from CREDITS.md: check licence and author** |
| Audio | Kenney audio packs + synthesized | CC0 | everything you hear | in game |
| Mushrooms, terrain, water, trip shaders, UI icons | made in code | ours | | in game |
| Uncle Fero, police, police car | Kenney Mini Characters / Car Kit (police car) or the artist | CC0 / ours | | needed |
| Mine set, chapel, rowboat, skeletons | Kenney Graveyard / Survival, Quaternius, or the artist | CC0 / ours | | needed |

Rules for new assets: free for commercial use (CC0 preferred, CC-BY is fine if credited), low-poly
flat-shaded, GLB/glTF, under ~5k triangles for props. Every new asset goes in `CREDITS.md` the same day.
Fab packs that are Unreal-only (`.uasset`) are out.

---

## 11. For the artist

The game is playable with free kits, but these are the places where custom art would give it its own
identity. Ordered by impact. Any tool is fine (Blender, Blockbench, MagicaVoxel exported to GLB, even
2D drawings we turn into textures); keep to the palette and the chunky low-poly style above.

**Characters (biggest impact)**
1. **The four friends**, our mascots: four distinct jobless outfits (tracksuit guy, reflective-vest guy,
   hoodie girl, rubber-boots girl), matching Kenney Mini Characters' rig so the animations still work.
2. **Babka Hela**: the face of the game. Headscarf, glasses, cardigan, apron. She should be lovable.
3. **The Hungry Hag**: the monster everyone will screenshot. Tall, thin, wrong. One concept sketch would
   already help a lot.
4. **The witch**, **Uncle Fero**, **the Nurse**, **the police officer**.

**Mushrooms (the collectibles)**
5. A **mushroom sheet**: the 16 species as clean low-poly models (or concept drawings we model), keeping
   each look-alike pair close but distinguishable (GDD §5). These also become the field guide pages.
6. **Field guide pages**: hand-drawn illustrations of each mushroom, in a folk/herbarium style, with
   Babka's handwriting notes. Shown in the journal (J).

**UI and branding**
7. **Logo** for the title screen and the store page.
8. **Folk pattern borders** and a paper texture for menus and the journal.
9. **Grave epitaphs** and village signs (can be text, but hand-lettered textures would be better).
10. **Key art**: four friends around the camp fire at dusk, a basket of glowing mushrooms, the Hag's
    silhouette between trees behind them. Used for the website hero and a Steam capsule.

**Places**
11. **Sanatórium Hôrka**: a Soviet mosaic for the lobby wall, signage, posters.
12. **The chapel** interior and the saint's coffin.
13. **The camp upgrade**: what the "house" looks like when bought (a sad shack with a satellite dish is
    funnier than a suburban house).

Deliver as GLB (models) or PNG (textures, illustrations, 1024 px or 2048 px). Drop them in
`godot/Mushroom/assets/art/` and add a line to `CREDITS.md`; the code swaps models in through
`_dress()` / `ModelFit.fit()` without touching colliders.
