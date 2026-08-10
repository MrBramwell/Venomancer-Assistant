# Venomancer Assistant

A World of Warcraft addon for Ascension's custom Venomancer class, built for the **Conquest of Azeroth** realm. Tracks your Brood Marks and Exposed Flesh stacks, gives you a dedicated bar for applying weapon venoms, and warns you about a few easy-to-miss states — all fully configurable, all draggable, all locked together with one setting.

## Features

### Stack Trackers
- **Brood Marks** — tracks your Spider Form stacking buff. Max 5.
- **Exposed Flesh** — tracks the Beetle Form stacking debuff. Max 10.
- Each tracker only shows while you're in the matching form (or while previewing/positioning).
- Configurable icon size, spacing, scale, and growth direction (Right / Left / Up / Down).
- **Early Warning tier**, independent from max-stack effects — get alerted before you actually cap out, with its own threshold, color, and effect set.
- **Max Stack effects**: glow border, pulse/scale bounce, color flash, particle burst, screen-edge flash, and sound — mix and match, each with its own color and an optional "sustain" mode that keeps repeating until the stacks clear instead of firing once.
- Per-tracker enable/disable, if you only want one of the two (or neither, if you're just here for the Venom Bar).
- Unified **Preview** control per tracker — pick a stack count and see exactly what happens at that count, including whichever warning/max effects it would trigger for real.

### Venom Bar
- Automatically scans your spellbook for known Venom spells — no hardcoded list, so anything added later just shows up.
- **Left-click** a venom to set it as your 1st selection, **right-click** for your 2nd.
- **Keybind** (Key Bindings → Venomancer Assistant → *Apply Selected Venom*) applies your 1st selection, then your 2nd on the next press — alternating with each press.
- **Middle-click** the apply button to cast Remove Venoms directly.
- Minimize to a single button that shows whichever selection is next up, or expand to see and reselect from the full row.
- Growth direction: Right / Left / Up / Down, same as the trackers.
- Shares the same Lock setting as everything else in the addon.

### Warnings
A dedicated tab for three generic alerts, each independently configurable:
- **Missing Venom** — fewer than 2 known venoms currently applied.
- **Missing Pheromone** — no Pheromone buff active.
- **Envenomed Weapons** — that buff isn't active.

Each can show as a small icon, on-screen text (with its own color, border color, size, and position — draggable, like everything else), a sound cue, or any combination.

### Everything Else
- Minimap button (toggleable) for quick access to options.
- One shared **Lock** setting freezes position for the trackers, the Venom Bar, and the warning text all at once — unlock it and each piece gets its own "Drag Me" handle and a visible bounding box while you reposition it.
- A tabbed, scrollable options panel: General, Brood Marks, Exposed Flesh, Venom Bar, Warnings.

## Installation

1. Download the latest release (or clone this repo).
2. Extract/copy the `VenomancerAssistant` folder into your `Interface\AddOns` directory.
3. Restart WoW or `/reload` if it's already running.

## Usage

Open the options panel any of these ways:
- `/va options` (or `/venomancer options`)
- Click the minimap button

### Slash Commands

| Command | Effect |
|---|---|
| `/va lock` | Lock all frame positions |
| `/va unlock` | Unlock for repositioning |
| `/va preview bm` | Preview the Brood Marks tracker |
| `/va preview ef` | Preview the Exposed Flesh tracker |
| `/va options` | Toggle the options panel |

`/venomancer` works as an alias for all of the above. `/bm` and `/broodmarks` also still work, for anyone used to the old addon name.

### Keybind

Set your Apply Venom keybind under **Key Bindings → Venomancer Assistant** in the standard WoW keybinding UI. No default key is set — bind whatever's comfortable.

## Configuration Notes

- **Brood Marks max (5) and Exposed Flesh max (10)** are fixed, not adjustable — these come directly from the in-game tooltips.
- The **Warning threshold** sliders are intentionally capped below their tracker's max, so an "early" warning can't accidentally overlap with the max-stack effects.
- Some icon choices (the three Warnings icons, in particular) are pulled from your actual spellbook where possible — Blight Venom for Missing Venom, Spider Pheromones for the Pheromone warning, Envenomed Weapons' own icon for that warning. If your character doesn't know one of those yet, a generic placeholder is used instead until you do.

## Known Limitations

This addon targets Ascension's custom client, which differs from standard WotLK API in a few places (e.g. `GetSpellTexture` instead of `GetSpellBookItemTexture`). It's been adjusted for the differences found so far, but if you hit an in-game Lua error, please open an issue with the error text — these client-specific quirks are usually a one-line fix once identified.

- Applying a venom works by casting the spell directly via a secure button, the same as clicking it in your spellbook. Changing your venom *selection* while in combat won't take effect until combat ends — that's a hard WoW restriction on secure frames, not a bug.
- The Venom Bar's apply mechanism assumes venoms apply the same way clicking them in your spellbook does. If Ascension's venoms need some other targeting step, let me know.

## Contributing

Issues and pull requests welcome. If you're reporting a bug, the in-game Lua error text (if any) is the most useful thing you can include.

## Credits

Built for a Venomancer main on Conquest of Azeroth, iterated extensively based on real in-game testing and feedback.
