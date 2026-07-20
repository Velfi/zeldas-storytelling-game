"""Real-world scale contract for the generated mystery-prop library.

All values are metres and describe the intended longest axis of the complete
asset.  Entries that bundle several objects use the footprint of the arranged
set, rather than the size of one member.
"""

from __future__ import annotations

import re


class WholeWordText(str):
    """Make scale routing use phrases, not accidental substrings.

    This prevents examples such as ``tag`` matching ``stage`` and ``cord``
    matching ``records``.
    """

    def __contains__(self, phrase):
        return re.search(rf"(?<![a-z0-9]){re.escape(phrase)}(?![a-z0-9])", self) is not None


EXACT_MAX_SPAN_M = {
    "Inspection rail carriage": 4.35,
    "Sleeping carriage interior kit": 3.80,
    "Exhibition plant cart": 2.05,
    "Silver garden prize cup": 0.62,
    "Cast-iron hose guide": 0.48,
    "Prize orchid and display pot": 1.15,
    "Engraved tasting spoon": 0.21,
    "Herb jars": 0.38,
    "Heavy mechanical metronome": 0.55,
    "Film projector": 0.78,
    "Violin, bow and fitted case": 0.84,
    "Rare hero bottle": 0.33,
    "Brass cartographer's divider": 0.30,
    "Modular tower scale model": 1.20,
    "Human body base": 1.75,
    "Articulated mannequin": 1.75,
    "Monkshood concentrate vial": 0.11,
    "Poison applicator / vial": 0.11,
    "Festival wristband": 0.24,
    "Survey weight": 0.32,
    "Carved boot sole": 0.31,
    "Brake shoe": 0.36,
    "Music-stand weight": 0.28,
    "Orchestral mute set": 0.32,
    "Stone sample block": 0.30,
    "Marble bookend pair": 0.48,
}


def target_max_span_m(name: str) -> float:
    """Return a reviewed, plausible longest-axis target for an inventory row."""
    if name in EXACT_MAX_SPAN_M:
        return EXACT_MAX_SPAN_M[name]
    key = name.lower()

    # Architecture and room-sized equipment.
    if any(x in key for x in ("connecting suite door", "projection booth door")):
        return 2.10
    if any(x in key for x in ("door", "entrance gate", "maintenance-ramp gate")):
        return 2.00
    if any(x in key for x in ("shelving", "shelves", "cloakroom racks", "baggage racks", "archive shelves", "suite furniture", "lounge furnishings")):
        return 1.90
    if any(x in key for x in ("food-stall", "preservation booth", "print press", "large-format printer")):
        return 1.85
    if any(x in key for x in ("ladder", "costume rack", "acoustic panel", "window-view panel", "practice-room acoustic")):
        return 1.60
    if any(x in key for x in ("table", "workstation", "workbench", "worktable", "drawing board", "editing bench", "console", "podium", "plinth")):
        return 1.50
    if any(x in key for x in ("cart", "trolley", "dumbwaiter", "lift", "wheeled pit cradle", "luggage chair")):
        return 1.45
    if any(x in key for x in ("seating", "chairs", "seat", "cage", "carrier", "wine rack", "flat file", "map drawers")):
        return 1.20
    if any(x in key for x in ("barrier", "hatch", "transom", "window", "backdrop", "curtain", "banner", "bunting", "sign stand")):
        return 1.20

    # Floor-standing props and grouped equipment.
    if any(x in key for x in ("double bass", "survey staff", "tide gauge")):
        return 1.65
    if any(x in key for x in ("tripod", "survey laser", "survey instrument", "music stand", "lectern", "plant collection")):
        return 1.20
    if any(x in key for x in ("crate", "road case", "pallet", "barrel", "hopper", "soil bin", "sacks", "suitcase", "trunk", "hat box")):
        return 1.00
    if any(x in key for x in ("projector", "recorder", "speaker", "monitor", "camera and surveillance", "control board", "control panel", "terminal", "cash till", "blower", "industrial fan", "gas line", "duct", "valve", "wash-station")):
        return 0.90
    if any(x in key for x in ("coat", "robe", "scarf", "bedding", "linen", "fabric")):
        return 1.15
    if any(x in key for x in ("plant", "orchid", "planter")):
        return 1.10

    # Tabletop, handheld, and evidence assets.
    if any(x in key for x in ("document", "letter", "invoice", "papers", "file", "folder", "record", "ledger", "log", "score", "script", "cue book", "permit", "photograph", "place-card", "ticket", "luggage tag", " tags", "register")):
        return 0.36
    if any(x in key for x in ("blueprint", "flat plans", "map weights", "straightedge")):
        return 0.90
    if any(x in key for x in ("key", "access set", "token", "seal", "latch", "catch", "lock", "bolt")):
        return 0.18
    if any(x in key for x in ("bottle", "vial", "jar", "decanter", "carafe", "glassware", "wine glasses", "tasting set")):
        return 0.38
    if any(x in key for x in ("tableware", "place setting", "place-setting", "plates", "bowls", "cutlery", "spoon", "cookware", "tray set", "cloches")):
        return 0.75
    if any(x in key for x in ("clock", "timer", "metronome", "gauge")):
        return 0.48
    if any(x in key for x in ("camera", "phone proxy", "tablet")):
        return 0.32
    if any(x in key for x in ("violin", "bow", "instrument", "strings")):
        return 0.85
    if any(x in key for x in ("tool", "knife", "letter opener", "divider", "brace", "guide", "sample", "wrench", "trowel", "shears")):
        return 0.55
    if any(x in key for x in ("cleaning", "sanitizer", "mop", "brush", "rope", "cords", " cord", "line", "hose", "rigging")):
        return 0.95
    if any(x in key for x in ("blood", "trace", "footprint", "shoeprint", "drag", "residue", "dust", "ash", "scratch", "chalk", "rosin")):
        return 0.90
    if any(x in key for x in ("film can", "film strip", "reel", "recording media")):
        return 0.45
    if any(x in key for x in ("bell", "chime")):
        return 0.38

    # Reviewed default for a single portable prop whose name has no family cue.
    return 0.80
