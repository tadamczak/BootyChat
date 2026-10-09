<p align="center"><img src="https://raw.githubusercontent.com/tadamczak/BootyLib/develop/Assets/readme-header.png" width="100%" alt="Sons of Mukla"></p>

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

- Global appearance with individual native-window overrides and independent copies.
- Font family, size, outline, shadow color and offset, and line spacing.
- Message fading, visibility time and fade duration.
- Background color, opacity and separate top/bottom/left/right margins; Booty gold borders with adjustable opacity.
- Separate tab width/height, solid or textured backgrounds, fonts, shadows, active/inactive text colors, border styles/colors and position offsets.
- Mouse-wheel speed, Shift-wheel to the top or bottom, optional scroll-button hiding.
- Native window-size overrides and input position, width, minimum height, gap and arrow-key behavior.
- Input fonts, shadows, background color and opacity, and native/project/dialog/tooltip borders.
- Shared appearance profiles including individual window overrides.
- Standalone configuration or the shared Booty Suite dashboard and settings.
- Native tabs, channels, filters, docking, menus and item links remain available.
- Bounded history of messages delivered to native windows, with literal text search and window filters.
- Live twelve-message pages, clickable native link preview, and copying a selected message or page.
- Optional history across sessions and explicit clearing for one window or all windows.
- Optional blocked phrases and repeated-message hiding, scoped to selected channels or player-message groups.
- Character-name and custom-phrase mentions, adjustable text color and optional sound with a cooldown.

This development build awaits verification in the game client.

## Installation

Place `BootyLib` and `BootyChat` directly inside `Interface/AddOns`. The folders
must have those exact names. Use the BootyLib supplied with this build.
Enable both in the character-selection addon list.
Booty Suite is optional. Restart the client after the first installation so the
new addon appears in the character-selection list.

## Usage

Use `/bc` or `/bootychat` to open Chat history, and `/bc settings` to open its settings.
Use `/bc disable` to restore the native appearance and `/bc enable` to apply
BootyChat again. These commands preserve your channels and messages.

Right-click a native chat tab to create, rename or filter tabs. Use the native
Unlock option, tab dragging and resize handle to position your windows.
Settings window numbers follow native chat slots. Chat > Global applies to all
windows until you change an individual setting. Each window's Settings source
offers Use global settings, Use individual settings and Copy global settings.
Use global settings removes that window's overrides and follows future Global
changes. Copy global settings creates a complete independent copy. Reset
appearance on the history toolbar also restores Global for the chosen window.
Width and height use sliders. Set window/input dimensions to zero to keep the native size. Tab width zero fits its caption; tab height zero keeps the native height. Native docking may cap tab widths to fit the dock. Docked windows share the
main window size. After detaching a window, its saved individual size applies
on the next setting change or native chat-window update.

Settings groups separate text, shadows, fading, backgrounds, scrolling, layout
and tabs. Native choices restore the corresponding WoW setting; tab inheritance
uses the chat text settings. Background margins extend the decorative surface.
Messages stay visible by default. Chat > Global > Fading lets you choose Native
or Fade messages when you want older lines to disappear; explicit saved choices
remain unchanged.
Input appearance keeps the native destination label, channel colors and typing
behavior. An explicit minimum input height also leaves room for its font;
width zero keeps the native width. Input and tab borders offer Native, None,
Project, Dialog and Tooltip, with separate color and opacity. Tab borders can
also inherit the window border. Horizontal and vertical tab offsets move the
tabs relative to their native dock positions.
Native chat background opacity keeps the original background. For the input,
native opacity restores the original artwork with Native border; custom borders
use a transparent fill until an explicit background opacity is selected.

Use the shared Profile page to add, save, load, delete or export an appearance
profile. Profiles include the common appearance, input options and individual
window overrides. Inherited window settings remain inherited after loading.
The profile's Reset defaults action also clears window overrides; Reset appearance
on the Chat history toolbar clears only the window you choose. Loading or resetting a profile
preserves whether BootyChat is enabled.

Chat opens directly to retained messages. `/bc history` opens the same page.
Search matches visible text literally; ASCII letters ignore case. Select a
window or All windows, then use Previous and Next for twelve-message pages.
The newest page updates automatically. Pause or browsing older pages keeps the
display stable; Live returns to the newest messages. Copying keeps a fixed
snapshot until you close the copy field. Refresh updates the current page.
Select a message to preview its complete text and native links. Copy
selected or Copy page opens a field with complete plain text; press Ctrl+C.

History starts with this session and does not import messages already visible
in native chat. Chat > History settings control collection, retention and
Remember history between sessions. The default is 500 messages shared by all windows;
the maximum is 2,000 messages and 256 KiB of original text. Individual messages
over 4,096 bytes are omitted from history while native chat continues normally.
Older messages are removed when a limit is reached. Reducing the limit also
removes older messages. Clear history asks for confirmation and clears the
selected window, or all windows, regardless of the current search query.

Cross-session saving is off by default. Enable it to retain history on logout
or UI reload. Disabling it removes the saved copy and keeps the current session.
History and its settings are separate from appearance profiles. Disabling
BootyChat or history collection keeps retained messages available for browsing.

Chat > Filters controls blocked phrases and repeated messages. Both start off.
Choose named channels, public chat, guild/party/raid/battleground chat, or all
player messages. Separate channel names and phrases with semicolons, for example
`World;Trade`. Channel names match exactly without their number or zone suffix;
an empty channel list covers all channels within the chosen scope. Blocked
phrases match visible message text literally. Set the repeat window from 1 to
120 seconds; repeats are checked separately in each native window.

Chat > Mentions starts off and has its own scope and channel list. Match your
character name, additional phrases, or both. Choose whole-word matching,
message color and an optional sound with a 1–60 second cooldown. Your own
messages do not trigger mentions. Incoming whispers retain their native alert.
Lists accept up to 32 phrases of 128 bytes each, or 16 channel names of 80 bytes
each. ASCII letters ignore case; other characters match exactly. Filtering and
mentions remain available when history collection is paused. Appearance profiles
preserve these preferences. Disabling BootyChat pauses all three features.

## Compatibility

BootyChat targets the original WoW 1.12 interface. Other addons which own the same
chat frames can conflict. Disable their chat customization before enabling
BootyChat; coexistence with third-party chat replacements is not yet verified.

If another addon changes scrolling while BootyChat is active, it keeps control
of the mouse wheel and BootyChat continues applying appearance settings. The
Chat page reports affected windows. Disable and enable BootyChat to apply its
scrolling again; your channels and messages remain available.

If another addon takes over a native window's message method after BootyChat
starts, history, filters and mentions for that window pause until BootyChat is disabled and
enabled again. Retained history is never inserted back into native chat.

Message filters affect native-window display. Loot, system, combat and NPC
messages are excluded; other addons still receive the original chat events.
BootyRaider continues receiving loot, roll and soft-reserve messages while chat
filters or history are active.
Hidden messages are omitted from BootyChat history and mention alerts. Native
whisper sounds and flashing tabs remain available even if a whisper is hidden.

Enter opacity as a number from 0 to 100; -100 selects native background opacity. Saved appearances and profiles keep their existing ratio format. Input distance accepts -512 to 512; negative values move the input toward/inside the main chat rectangle. Each background margin is adjustable independently from 0 to 256. Tab backgrounds offer native, solid color, Dialog and Tooltip textures with color tint and opacity.

After unlocking a chat window, drag its native tab and release the mouse to finish. Disabling BootyChat also cancels an unfinished drag.
