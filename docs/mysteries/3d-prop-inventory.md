# Mysteries of The City — 3D Prop Inventory

This is the production inventory for all sixteen planned mysteries. It surveys
the case designs in this directory and the current `assets/` library.

## Scope and status

The list includes portable objects, furniture, machinery, vehicles, architectural
fixtures that must move or carry evidence, and visible clue states. It excludes
characters, clothing already skinned to characters, whole buildings, terrain,
particles, UI-only diagrams, and ordinary architectural walls and floors.

Status codes:

- **Reuse:** a current asset is adequate after material and scale adjustment.
- **Variant:** start from a current asset but author case-specific geometry or states.
- **New:** the shape or interaction requires a new model family.
- **Set piece:** a large interactive model that should be planned with its level.

The repository currently contains 431 GLB files. The Kenney furniture, city,
industrial, road, and car kits cover most generic chairs, tables, cabinets,
desks, shelving, kitchen units, sofas, lamps, boxes, stairs, buildings, streets,
and road vehicles. Existing project assets also cover books, bookshelves, rugs,
bloodstains, a body base, a ledger, cloth, a stopped watch, a bottle, a cane, and
a statuette. Those assets should be reused rather than rebuilt unless a clue
requires a different silhouette or movable part.

## Shared interactive prop families

These should be authored once and instanced or given material variants across
campaigns.

| Prop family | Status | Required variants or states |
| --- | --- | --- |
| Human body base | Variant | Contemporary body variants; lying, fallen, seated/staged; removable coat and trace sockets |
| Blood evidence | Variant | Pool, transfer smear, impact spatter, wiped residue, blood inside a joint; decal plus optional shallow mesh |
| Trace evidence markers | New | Soil, grit, clay, rosin, plaster, dust, grease, fibers, ash, condensation and residue patches |
| Footprints and shoeprints | New | Wet full print, stamped flat print, partial print, drag trace, boot tread impression |
| Wheel and drag traces | New | Narrow cart, trolley, luggage chair, instrument case, pit cradle, and body drag variants |
| Generic document set | Variant | Single sheet, folded letter, note, invoice, permit, report, contract, log, score and blueprint materials |
| Bound records | Reuse/variant | Ledger, register, cue book, room log, casebook and menu covers |
| Folder and case-file set | New | Open/closed folders, tabbed file, sealed OMQ capstone file, photo and evidence sleeves |
| Photograph set | New | Loose print, instant print, framed photo, contact sheet; swappable image material |
| Keys and access set | New | House key, cabinet key, hotel key/fob, rail service key, key ring, claim token |
| Locks and latches | New | Door lock, service latch, service catch, transom key return, broken bolt; open/closed states |
| Glassware set | New | Water, wine, tasting and whisky glasses; empty/full, condensation ring and rim-residue states |
| Bottle set | New | Wine, chemical, sanitizer and dye bottles; sealed/open, dusty/clean, chilled/condensed states |
| Tableware set | New | Plates, tasting bowls, serving bowls, engraved spoon, cutlery and place settings |
| Labelled container set | New | Herb jar, poison vial, sample jar, film can, evidence jar; removable lids and swappable labels |
| Cart and trolley base | New | Platform cart, plant cart, linen trolley, serving trolley; clean/damaged wheel variants |
| Storage crate set | Reuse/variant | Cardboard boxes plus wood crates, archive boxes, instrument trunks and bottle cases |
| Desk and task lighting | Reuse | Existing table, floor, wall and ceiling lamps with campaign material variants |
| Clocks and timers | New | Mantel clock, wall clock, kitchen timer, cue clock; running/stopped and adjustable hands |
| Audio recorder and speaker | Variant | Contemporary-timeless recorder, portable speaker, playback controls and recording media |
| Camera and surveillance set | New | Fixed security camera, handheld camera/phone proxy, monitor bank; adjustable aim |
| Computer workstation | Reuse/variant | Existing screen, keyboard, mouse and laptop; profession-specific screen materials |
| Display frame | New | Seating chart, map, poster, program and photograph frames with removable backing |
| Coat and fabric evidence | New | Empty hanging coat, robe, scarf, coat thread, torn fabric and folded cloth states |
| Ropes, cords and lines | New | Rigging rope, cut safety line, survey cord and utility rope; intact/cut/coiled states |
| Cleaning set | New | Cloth, mop, bucket, sanitizer pump, spray bottle and cleaning caddy |
| Tool and sample set | New | Generic hand tools, adjustment key, sample blocks, tweezers and evidence dish |

## Bellwether Mysteries

### The Last Garden Prize

| Prop | Status | Notes |
| --- | --- | --- |
| Silver garden prize cup | New | False weapon; clean and handled states |
| Cast-iron hose guide | New | True weapon; clean and blood-in-crevice states |
| Exhibition plant cart | New | Movable; wheel-track footprint; bent latch |
| Bent cart latch | New | Separate inspectable part with coat thread socket |
| Prize orchid and display pot | Variant | Use foliage base; watered/unwatered soil states |
| Conservatory plant collection | Reuse/variant | Existing plants plus flowering and specimen variants |
| Potting bench | Variant | Existing table with soil-resistant top and lower shelf |
| Soil bin | New | Open/closed; hides hose guide |
| Soil and compost sacks | New | Stacked, open and spilled variants |
| Watering can, hose and nozzle | New | Hose may be spline geometry; wet/dry states |
| Garden hand-tool set | New | Trowel, fork, shears, dibber and labels |
| Pesticide bottle and cabinet | New | Supports Eli's separate wrongdoing |
| Conservatory entrance mat | Reuse/variant | Existing rug; lifted state reveals wheel marks |
| Spare key and service-door latch | New | Demonstration-ready moving latch |
| Exhibition tables, signs and ribbons | Reuse/variant | Existing tables; new sign and ribbon meshes |

### The Last Performance at Bellwether Hall

| Prop | Status | Notes |
| --- | --- | --- |
| Stage brace | New | True weapon; folding hinge and blood residue state |
| Rolled theatrical backdrop | New | Rolled, partly unrolled and hung states; body-width crease |
| Fly-system rigging set | Set piece | Battens, pulleys, counterweights, ropes and gallery rail |
| Cut safety line | New | Intact and cut variants with inspectable end |
| Lighting console | New | Cue controls and editable cue-log screen |
| Stage lighting instruments | New | Fresnel/profile fixtures, barn doors and clamps |
| Cue-light unit | New | Red/green emissive states |
| Rehearsal ladder | Variant | Existing stairs insufficient; rolling theater ladder |
| Costume rack and hangers | New | Movable garments; bead evidence socket |
| Costume bead and thread traces | New | Inspectable hero bead plus small scatter |
| Script, cue book and stolen pages | Variant | Shared document family |
| Prop crates and road cases | Variant | Shared storage family |
| Auditorium seating | New | Modular rows, aisle-end and folded-seat states |
| Music stand / lectern | New | Reusable in concert case |

### A Recipe for Silence

| Prop | Status | Notes |
| --- | --- | --- |
| Engraved tasting spoon | New | Hero clue; clean, coated and dye-demo states |
| Tasting bowls and judging plates | New | Reusable tableware family |
| Competition cookware | New | Pots, pans, trays, mixing bowls and utensils |
| Herb jars | New | Dated and undated labels; swappable contents |
| Monkshood concentrate vial | New | Small hero poison container |
| Pantry sealing-wax set | New | Wax stick, seal and broken jar seal |
| Kitchen timer set | New | Multiple readable timer faces |
| Prep workstation modules | Variant | Existing kitchen cabinets and bars with stainless tops |
| Wash-station sink and sprayer | Variant | Existing sink plus commercial sprayer and drainboard |
| Sanitizer dispenser | New | Interrupted/used level states |
| Dish racks and bus tubs | New | Spoon return path dressing |
| Serving trolley | Variant | Shared cart base |
| Ingredient crates and sacks | Variant | Shared storage family |
| Harmless dye bottle and demo tray | New | Finale demonstration state |
| Sponsor and contestant signs | New | Swappable flat sign materials |

### Death on the Promenade

| Prop | Status | Notes |
| --- | --- | --- |
| Survey weight | New | True weapon; wipeable eyelet residue |
| Survey case | New | Fiber source; open/closed states |
| Survey tripod and instrument | New | Reusable in Blackthorn cartography case |
| Bright coat | New | Wearable and empty hanging variants |
| Festival wristband | New | Character-worn and photographic evidence variant |
| Food-stall counter and canopy | Variant | Existing city kit plus folding service modules |
| Cash till / point-of-sale terminal | New | Readable transaction state |
| Preservation booth | Variant | Reusable market-stall structure |
| Festival banners and bunting | New | Wind-capable or static variants |
| Crowd barriers and sign stands | New | Modular festival dressing |
| Tide gauge / quay depth marker | New | Readable water-level reference |
| Maintenance-ramp gate | New | Open/closed fixture and drag-contact states |
| Permit folder and crowd counter | Variant | Shared document and handheld counter |
| Handheld camera / phone proxy | New | Provides photograph clue without brand specificity |

## One More Question

### The Final Cut

| Prop | Status | Notes |
| --- | --- | --- |
| Film projector | New | Running/stopped, open gate and projector-beam origin |
| Projector reels | New | Full, partial and empty winding states |
| Film cans and labels | New | Swappable labels; one hides removed frames |
| Workprint film strip | New | Fresh splice, missing-frame and loose-strip variants |
| Editing bench | New | Rewinds, viewer, bins and work surface |
| Film splicer and tape | New | Hero workstation tools |
| Editing waste bin | Variant | Existing wastebin with film-dust contents |
| Screening-room seats | New | Modular row; one movable seat with blood below |
| Projection booth door | Set piece | Sound-insulating door and inspectable threshold |
| Film-vault shelving | Variant | Existing shelves with reel-sized bays |
| Voice recorder / playback unit | Variant | Shared audio family |
| Studio case board | New | Open episode files and sealed capstone display |

### A Private Performance

| Prop | Status | Notes |
| --- | --- | --- |
| Heavy mechanical metronome | New | True weapon; working pendulum and residue state |
| Violin, bow and fitted case | New | Reused by Blackthorn violin case |
| Double bass and wheeled case | New | Case supports body movement and wheel trace |
| Music stands | New | Folded, raised and fallen states |
| Orchestral mute set | New | Dropped mute is a timeline clue |
| Printed score and marked score | Variant | Shared document family with page-open states |
| Rosin block and rosin dust | New | Object plus trace decal |
| Recording console | New | Sliders, meters and editable display material |
| Studio monitors and microphones | Variant | Existing speakers plus new mic/stand set |
| Waveform display | Variant | Existing computer screen with authored material |
| Instrument racks | New | Violin, bow and case storage modules |
| Acoustic panels and diffusers | New | Wall-mounted dressing with reusable modules |
| Conductor's podium and music desk | New | Reusable concert-hall set piece |

### The Perfect Vintage

| Prop | Status | Notes |
| --- | --- | --- |
| Modular wine rack | New | Upright, loosened and collapsed states |
| Wine-bottle family | New | Shapes, colors, labels, dust and condensation states |
| Rare hero bottle | New | Warm, chilled and substituted-identical variants |
| Bottle cradle | New | True weapon; moving joints and hidden residue |
| Narrow bottle lift | Set piece | Platform, shaft doors and controls; body-transfer scale |
| Wine glasses and tasting set | New | Shared glassware family |
| Decanter and funnel | New | Cellar/tasting dressing |
| Bottle thermometer and cellar gauge | New | Readable temperature cues |
| Wine crates and straw packing | Variant | Shared storage family |
| Cellar worktable | Variant | Existing table with bottle tools |
| Rack fasteners and repair tools | New | Loose hardware supports staged collapse |
| Carpet sample / tasting-room carpet | Variant | Existing rug plus loose comparison swatch |
| Cellar inventory book | Variant | Shared ledger family |

### The Architect's Model

| Prop | Status | Notes |
| --- | --- | --- |
| Modular tower scale model | Set piece | Floors, walls and removable barrier; comparison centerpiece |
| Scale-model barrier | New | Original/added states with visible adhesive |
| Model-making tool set | New | Knife, ruler, tweezers, glue and cutting mat |
| Fresh and aged adhesive | New | Tube plus trace states |
| Stone sample block | New | True weapon; clean and porous blood states |
| Plaster and finish sample set | New | Full-size and labelled comparison samples |
| Blueprint rolls and flat plans | Variant | Shared document family |
| Service-lift interior padding | Set piece | Clean and fiber-bearing states |
| Construction safety set | New | Hard hats, cones, barriers, vest and warning signs |
| Material pallet | Variant | Existing boxes plus tile, stone and plaster stacks |
| Survey laser / level | New | Reuse survey tripod family where possible |
| Site camera / inspection tablet | Variant | Shared camera/computer family |

## The Marigold Circle

### Murder in the Marigold Rooms

| Prop | Status | Notes |
| --- | --- | --- |
| Murder knife / letter opener | New | Hero weapon must be fixed during script authoring |
| Linen trolley | Variant | Shared cart base; damaged wheel and fiber states |
| Linen stacks and laundry bags | New | Body concealment and corridor dressing |
| Stopped mantel clock | New | Movable hands and manual-stop state |
| Recording player | New | Contemporary-timeless physical playback device |
| Recording media and sleeve | New | Missing sleeve and labelled recording states |
| Phonograph / media cabinet | Variant | Existing cabinet with fitted player interior |
| Conservatory planter and soil | Variant | Existing plant/planter plus trace states |
| Formal dining table and chairs | Reuse | Existing tables and chairs with Marigold materials |
| Formal place-setting set | New | Shared tableware and glassware families |
| Cloakroom racks and claim tokens | Variant | Existing coat rack plus new hangers/tokens |
| Foundation papers, loan and sale files | Variant | Shared document family |
| Service bell / audible chime | New | Visual object tied to repeated background sound |

### Five Places at Dinner

| Prop | Status | Notes |
| --- | --- | --- |
| Five matched wine glasses | New | Full/empty, moved, rim-poison and condensation states |
| Place-card set | New | Movable named cards with fingerprint overlays |
| Framed seating chart | New | Original/corrected layers and removable backing |
| Wine bottle and serving carafe | New | Shared wine family |
| Poison applicator / vial | New | Small hero object |
| Caterer's kit | New | Knife roll, bottles, cloths and planted-poison socket |
| Serving trays and cloches | New | Formal service dressing |
| Formal five-place table setting | New | Uses shared tableware family |
| Gallery display plinths | New | Reusable collection-gallery modules |
| Art frames and sculptural placeholders | Variant | Existing statuette plus new frames/plinth materials |
| Reflection-bearing framed artwork | New | Provides preserved table-composition clue |
| Family letter and invoices | Variant | Shared document family |

### The Guest in Suite 808

| Prop | Status | Notes |
| --- | --- | --- |
| Marble bookend pair | New | True weapon; clean and blood-in-felt states |
| Connecting suite door | Set piece | Sticking lower edge, paint-transfer and open/closed states |
| Hotel key and key-log terminal | New | Shared key set plus readable terminal |
| Gala coat | New | Wearable and staged-on-body variants |
| Coat-check ticket and claim rack | New | Token, ticket and numbered rack system |
| Room-service tray set | New | Tray, dome, crockery, receipt and pen |
| Signature pad / register | Variant | Shared document or computer family |
| Historical letters and packet | Variant | Shared document family with tied/open states |
| Dumbwaiter | Set piece | Car, hatch and controls; not a body route |
| Hotel luggage and bell cart | New | Reusable travel props |
| Suite furniture | Reuse | Existing beds, desks, chairs, tables and lamps |
| Archive shelves and boxes | Reuse/variant | Existing bookcases and boxes with hotel labels |

### The Sleeper Across the City

| Prop | Status | Notes |
| --- | --- | --- |
| Sleeping carriage interior kit | Set piece | Compartment shell, bunks, corridor and doors |
| Rail service catch | New | Demonstration-ready lock mechanism |
| Luggage chair | New | Movable; wheel grease and body-transfer states |
| Robe | New | Wearable and empty silhouette variants |
| Tickets, sleeves and luggage tags | New | Movable identity and room-assignment set |
| Suitcases, trunks and hat boxes | New | Reusable hotel/rail luggage family |
| Attendant's key ring and punch | New | Rail-specific access set |
| Rope coil and fiber trace | New | Shared rope family |
| Compartment bedding | New | Pillows, blankets and disturbed states |
| Observation-lounge furnishings | Reuse | Existing sofas, chairs, tables and lamps |
| Dining-car place settings | Reuse/new | Reuse shared Marigold tableware |
| Baggage racks and shelving | New | Carriage-specific modular storage |
| Window-view panels | Set piece | Swappable City views to communicate train movement |

## The Blackthorn Papers

### The Ashes of Blackthorn Lane

| Prop | Status | Notes |
| --- | --- | --- |
| Brass cartographer's divider | New | True weapon and drawing tool; blood-joint state |
| Survey staff | New | Socket accepts carved sole; demonstration-ready |
| Carved boot sole | New | Separate hero clue and mounted state |
| Wet stamped footprints | New | Flat-pressure print sequence and partials |
| Workroom key | New | Shared key set |
| Operable transom | Set piece | Key-return path; open/closed states |
| Burned tracing-linen remains | New | Decoy fragments and ash-fiber close state |
| Intact tracing linen and maps | New | Rolled, flat, folded and burned-edge variants |
| Cartographer's drawing board | New | Pressure-impression reveal material/state |
| Map weights and straightedges | New | Professional table dressing |
| Survey tripod and instrument | Reuse/new | Share Bellwether survey set |
| Print press / large-format printer | Set piece | Timeless hybrid print-room equipment |
| Map drawers / flat file | New | Openable shallow drawers |
| Clay sample containers | New | Shared labelled-container family |
| Sales ledger and field note | Variant | Shared records and document family |

### The Violinist Without a Shadow

| Prop | Status | Notes |
| --- | --- | --- |
| Violin, bow and case | Reuse/new | Share OMQ orchestra family |
| Music-stand weight | New | True weapon; residue state |
| Music stand | Reuse/new | Share orchestra family |
| Articulated mannequin | New | Dressed/undressed and movable states |
| Spare scarf | New | Worn, draped and fiber-trace states |
| Playback recorder and speaker | Variant | Shared audio family |
| Practice-room acoustic panels | Reuse/new | Shared orchestra family |
| Replacement strings and packet | New | Sabotaged/intact variants |
| Room-booking log | Variant | Shared ledger or computer material |
| Courtyard bell | New | Visible time/audio landmark |
| Angled glass passage panels | Set piece | Reflection proxy with authored state/material |
| Recital chairs and podium | Reuse | Existing chairs plus concert podium |

### The Red Fog of South Quay

| Prop | Status | Notes |
| --- | --- | --- |
| Industrial yard blower | Set piece | Running/stopped; accepts dust hopper |
| Iron-oxide hopper and powder | New | Fill states and residue decals |
| Maintenance gas line | Set piece | Modular pipe with vent endpoint |
| Corroded and replacement valves | New | Removed, fitted and retained variants |
| Remote control panel | New | Authored manual sequence display |
| Industrial fans | New | Running/stopped blades and direction indicator |
| Vent grilles and duct modules | New | Supports airflow demonstration |
| Gas detector / meter | New | Readable safe/detected states |
| Evidence sample dishes | New | Reusable laboratory container family |
| Smoke-test canister | New | Finale airflow demonstration prop |
| Bird cages and perches | New | Healthy-animal environmental proof |
| Animal carriers and rescue kit | New | Explains Lena's trespass |
| PPE set | New | Respirator, goggles, gloves and hard case |
| Pipe tools and shutdown kit | New | Wrenches, lockout tags and damaged part |
| Industrial barrels and pallets | Reuse/variant | Existing industrial kit dressing |

### The Empty Carriage

| Prop | Status | Notes |
| --- | --- | --- |
| Inspection rail carriage | Set piece | Exterior and explorable interior; movable one-car-length state |
| Wash-track rail car | Set piece | Distinct body-discovery car |
| Brake shoe | New | True weapon; clean and residue states |
| Floor hatch and hidden bolt | Set piece | Open/closed, bolted/broken and grease-transfer states |
| Wheeled pit cradle | New | Body-transfer capacity and wheel-trace state |
| Maintenance pit modules | Set piece | Rails, walkways, ladder, drainage and cradle path |
| Rail chalk marks | New | Before/after wheel-position decals |
| Fixed depot cameras | New | Reuse shared surveillance family |
| Window scratch | New | Swappable carriage-window material/decal states |
| Switch-booth control board | Set piece | Manual movement controls and contact indicators |
| Brake grease and residue | New | Shared trace family |
| Tool-bay rack and rail tools | New | Brake tools, wrenches, jacks and inspection lamps |
| Wash-track brushes and nozzles | Set piece | Static or simple running states |
| Inspection photographs | Variant | Shared photograph family |
| Depot barriers and safety signs | Reuse/variant | Share construction/industrial safety set |

## Non-case campaign and hub props

### Bellwether hub

- Bookshop counter, rolling library ladder and display stands — **Variant/New**
- Mystery novels, newspapers, postcards and community notices — **Variant**
- Neighborhood map and case pins — **New**
- Case souvenirs: prize ribbon, theater program, engraved spoon facsimile and festival photograph — **New/Variant**
- Seasonal planters, café tables, benches, bins and street lamps — **Reuse**
- Memorial flowers, repaired signs and post-case location-state props — **Variant**

### One More Question office frame

- Lieutenant's desk, visitor chair, filing cabinets and coat rack — **Reuse**
- Four-position case board with three open files and one sealed capstone — **New**
- Evidence-photo clips and completion markers — **New**
- Campaign souvenirs: film frame, mute, bottle label and model fragment — **New/Variant**
- Desk telephone, coffee cup and pencil cup — **New**

### Marigold continuity dressing

- Foundation portrait frames, donor plaques and club notice board — **New**
- Recurring club tableware, floral centerpiece and branded-but-fictional stationery — **New**
- Investigator's travel case and reconstruction board — **New**
- Rail excursion luggage labels referencing prior institutions — **Variant**

### Blackthorn casebook frame

- Physical Blackthorn casebook with tabbed paper sections — **New**
- Companion's writing desk, manuscript stack and fountain pen — **New/Variant**
- Three precedent mementos: carved print, mirrored glass shard and red residue vial — **New**
- Master-case deduction board with pinned rail diagram — **New**
- Resume-point marker/bookmark for suspended-case transitions — **New**

## Production grouping

### Priority A — reasoning-critical hero props

Build these before detailed environments because the mysteries cannot be
validated without their geometry or state changes:

1. Shared traces, documents, keys, locks, photographs, glassware and containers.
2. Garden cart, hose guide, trophy and service latch.
3. Stage brace, backdrop and fly-line components.
4. Engraved spoon, herb jars and wash-station props.
5. Survey weight, coat, wristband and tide gauge.
6. Projector, film workflow and movable screening seat.
7. Metronome, bass case, score, mute and recording console.
8. Bottle lift, rack, hero bottle and bottle cradle.
9. Scale model, removable barrier, stone and plaster samples.
10. Linen trolley, stopped clock and recording player.
11. Five-glass/place-card/seating-chart system.
12. Bookends, connecting door and hotel identity props.
13. Luggage chair, service catch and ticket/tag system.
14. Divider, survey-staff sole, footprints, transom and impression board.
15. Reflection passage, mannequin, violin and playback system.
16. Blower, pipe/valve/fan system and gas detector.
17. Rail carriage, hatch, pit cradle, brake shoe, chalk and switch controls.

### Priority B — reusable profession kits

- Gardening and exhibition kit
- Theater rigging and backstage kit
- Commercial cooking and table-service kit
- Surveying and cartography kit
- Film projection and editing kit
- Orchestra and recording kit
- Wine cellar and tasting kit
- Architecture studio and construction kit
- Private club and formal dining kit
- Hotel and travel kit
- Rail passenger and depot-maintenance kit
- Industrial ventilation and safety kit

### Priority C — atmosphere and hub continuity

Build only after clue routes work: dense shelf contents, repeated crockery,
decorative instruments, extra luggage, posters, donor plaques, generic tools,
festival clutter, flowers, and case souvenirs.

## Modeling requirements

- All props use the project convention: right-handed, Y-up, +Z forward.
- Clue-critical faces need sufficient texel density for residue, scratches,
  handwriting and material comparison.
- Every stateful prop should expose named nodes rather than require whole-model
  swaps where practical: `door`, `latch`, `lid`, `wheel`, `hands`, `reel`,
  `hatch`, `valve`, `barrier`, and similar parts.
- Keep pristine and evidentiary materials separate so inspection state does not
  require changing unrelated surfaces.
- Small clues need a readable inspection presentation even if their world mesh
  remains physically scaled.
- Large set pieces must be tested against authored character paths, body routes,
  sightlines, and travel times before decorative passes.
- Documents may share one set of shallow meshes with case-specific textures;
  do not author unique geometry for every letter or report.
- Repeated bottles, glasses, plants, chairs and boxes should use instancing and
  material variants.
