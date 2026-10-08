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
- Font family, size, outline, shadow color and offset, and line spacing.
- Message fading, visibility time and fade duration.
- Background color, opacity and margins; Booty gold borders with adjustable opacity.
- Separate tab fonts, shadows, active/inactive caption colors and gold borders.
- Mouse-wheel speed, Shift-wheel to the top or bottom, optional scroll-button hiding.
- Native window-size overrides and input position, minimum height, gap and arrow-key behavior.
- Input fonts, shadows, background color and opacity, and project gold border.
- Shared appearance profiles including individual window overrides.
- Standalone configuration or the shared Booty Suite dashboard and settings.
- Native tabs, channels, filters, docking, menus and item links remain available.

This development build awaits verification in the game client. Persistent
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

Settings groups separate text, shadows, fading, backgrounds, scrolling, layout
and tabs. Native choices restore the corresponding WoW setting; tab inheritance
uses the chat text settings. Background margins extend the decorative surface.
Input appearance keeps the native destination label, channel colors and typing
behavior. An explicit minimum input height also leaves room for its font.
Native chat background opacity keeps the original background. For the input,
native opacity restores the original artwork when its project gold border is
off; with that border on, it selects a transparent custom fill.

Use the shared Profile page to add, save, load, delete or export an appearance
profile. Profiles include the common appearance, input options and individual
window overrides. Inherited window settings remain inherited after loading.
The profile's Reset defaults action also clears window overrides; Reset window
on the Chat page clears only the selected window. Loading or resetting a profile
preserves whether BootyChat is enabled.

## Compatibility

BootyChat targets the original WoW 1.12 interface. Other addons which own the same
chat frames can conflict. Disable their chat customization before enabling
BootyChat; coexistence with third-party chat replacements is not yet verified.

If another addon changes scrolling while BootyChat is active, it keeps control
of the mouse wheel and BootyChat continues applying appearance settings. The
Chat page reports affected windows. Disable and enable BootyChat to apply its
scrolling again; your channels and messages remain available.
