# Qloot

**Qloot** is a high-performance, quick loot addon designed specifically for World of Warcraft 3.3.5a (Wrath of the Lich King). 

Unlike standard fast loot addons that try to grab everything instantly-often causing disconnects on private servers-Qloot uses a smart queuing system. It processes items one by one with a configurable micro-delay, ensuring your connection stays stable while still feeling incredibly fast.

## Features

- **Queue-Based Looting:** Items are added to a processing queue rather than looted in a tight loop.
- **Server Safety:** Configurable delay (default 110ms) prevents packet flooding and disconnects.
- **Freeze Protection:** Prevents "burst" looting after lag spikes or Alt-Tabbing.
- **Smart Validation:** 
  - Checks if a slot is still valid before looting.
  - Skips Locked/BoP items automatically (opening the window for you to decide).
  - Pre-calculates inventory space and stack sizes to avoid error spam.
- **Leftover Warning:** Alerts you if items were left unlooted when the window closes.
- **Debug Mode:** Optional verbose logging to chat for troubleshooting loot issues.

![Qloot 1](https://github.com/mmobrain/stuffforstuff/blob/main/Qloot/1.jpg?raw=true)



## Comparison: Leatrix Plus vs. Qloot

Qloot was built to address specific shortcomings in older auto-loot implementations on modern private server cores.

| Feature | Leatrix Plus (3.3.5a) | Qloot |
| :--- | :--- | :--- |
| **Looting Method** | Instant loop with conditional delays | Queue-based with guaranteed throttle |
| **Alt-Tab Safety** | None (prone to packet bursts) | `math.min(elapsed, 0.1)` throttle cap |
| **Delay Enforcement** | Conditional (often skipped) | Always enforced via OnUpdate engine |
| **Queue System** | No queue (fire and forget) | Persistent queue with re-validation |
| **State Recovery** | None (relies on initial event) | Re-validates slots before *every* loot action |
| **Inventory Check** | Yes, but performed in tight loop | Yes, performed before queuing specific items |

## Installation

1. Download the latest release.
2. Extract the `Qloot` folder.
3. Move the folder to your `Wow/Interface/AddOns/` directory.

## Usage

Qloot works automatically out of the box. 

- **Shift-Right Click:** Temporarily disable auto-loot (manual loot).
- **Locked Items:** If an item is Master Looted or Bind on Pickup, Qloot will open the loot window for you to handle it manually.
- **Full Inventory:** The loot window will remain open if your bags are full.

### Commands

Type `/qloot` to open the configuration panel.

- **Enable Auto Loot:** Toggle the entire addon.
- **Loot Delay:** Adjust the speed (50ms - 500ms). *Recommended: >=110ms.*
- **Warn Leftover Items:** Toggle warnings for unlooted items.
- **Debug Mode:** Enable detailed chat logs of what Qloot is doing.

## Requirements
*   **Game Version**: 3.3.5a (Wrath of the Lich King)

## Credits
*   **Author:** Skulltrail

## License
This project is released under the [MIT License](LICENSE.md).