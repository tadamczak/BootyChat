<p align="center"><img src="https://raw.githubusercontent.com/tadamczak/MuklaOfficerSuite/master/Assets/readme-header.png" width="100%" alt="Sons of Mukla"></p>

# BootyChat

BootyChat customizes the native World of Warcraft 1.12 chat. Keep your own tabs,
channels and filters while adjusting fonts, backgrounds, project gold borders,
scrolling and the shared input box.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Compatibility](#compatibility)

## Features

- Common appearance with individual native-window overrides.
- Font family, size and outline; background color and opacity; Booty gold borders.
- Mouse-wheel speed, Shift-wheel to the top or bottom, optional scroll-button hiding.
- Native window-size overrides and input position, font size and arrow-key behavior.
- Standalone configuration or the shared Booty Suite dashboard and settings.
- Native tabs, channels, filters, docking, menus and item links remain available.

This first development build awaits verification in the game client. Persistent
message history, search, copying, spam filters and mentions are planned additions.

## Installation

Place `BootyLib` and `BootyChat` directly inside `Interface/AddOns`. The folders
must have those exact names. Enable both in the character-selection addon list.
Booty Suite is optional. Restart the client after the first installation so the
new addon appears in the character-selection list.

## Usage

Use `/bc` or `/bootychat` to open Chat, and `/bc settings` to open its settings.
Use `/bc disable` to restore the native appearance and `/bc enable` to apply
BootyChat again. These commands preserve your channels and messages.

Right-click a native chat tab to create, rename or filter tabs. Use the native
Unlock option, tab dragging and resize handle to position your windows.
Settings window numbers follow native chat slots. Common appearance applies
until you change an individual window setting; Reset window restores inheritance.
Set width or height to zero to keep the native size. Docked windows share the
main window size. After detaching a window, its saved individual size applies
on the next setting change or native chat-window update.

## Compatibility

BootyChat targets the original WoW 1.12 interface. Other addons which own the same
chat frames can conflict. Disable their chat customization before enabling
BootyChat; coexistence with third-party chat replacements is not yet verified.
