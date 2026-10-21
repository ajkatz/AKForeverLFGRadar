# AKForeverLFGRadar

Pick a dungeon and see how far you are from its door - and how far everyone else running the addon is.
For WoW: Forever.

`/dr deadmines` (a name, a tag such as `sfk` or `brd`, or a part of a name) picks the dungeon; the panel
then says, for you and for everyone heard from:

| Answer | When |
|---|---|
| `inside` | you are in that very instance |
| `at the entrance` | within sixty yards of the door |
| `1,240 yd` | on the door's continent, your spot known - with the zone's name when it is another zone |
| `in Westfall` | the door's zone, when the client gives no coordinates (some maps do not) |
| `another continent` | the door's continent is not yours |
| `in Elwynn Forest`, `in Gnomeregan` | somewhere else, by zone - or inside another instance |

## How the others get on your panel

Everyone with the addon joins a hidden chat channel (`AKLFGRadar`, never added to a chat window) and
tells it where they are - their spot, not a distance - every 15 seconds while moving, every minute
regardless. So every panel measures everyone against **its own** pick, nearest first, with the other
person's own pick as a tag when it differs (`> SFK`). `/dr list` says how many are heading where.
`/dr share off` keeps your position to yourself; you still see the others.

The door of each dungeon starts from a built-in table (the mine mouth, the cave, the gate as players know
them - to about a percent of the zone map), takes the client's own map pin when this client has one for
the old world, and is **learned** for good by the first addon user who walks in: the last spot before the
instance is the door, kept for every character and told to the others. Forever's own instances have no
seed, so they know only their zone until somebody walks in.

## In the game's own group finder

Forever's group finder is Blizzard's vanilla-style one. The radar follows it and reads it, and writes nothing
into it:

- **The pick follows the finder, and a pick searches.** List yourself for a dungeon, or filter the Browse
  tab to one (or to every wing of one), and the radar picks that dungeon. Pick one from the panel's dropdown,
  or by `/dr <dungeon>`, and a search for it runs at once - a search of ours (a click or a command, as the
  client demands of that search); the finder's Browse list shows the results, since it draws the client's
  last search. The finder's own dropdown is never written: a filter set there from an addon leaves tainted
  values behind, and the finder's next search of its own outside a click is then blocked by the client
  ("Interface action failed because of an AddOn"). So its dropdown keeps its own choice until you change it
  there - and the pick follows.
- **The list, people and groups, sorted by proximity and role.** Whatever the finder last searched, every
  listing for the picked dungeon comes to the panel - a person alone or a group, as the finder has them -
  with the roles on offer, the leader's level and class, the group's size, and a proximity: the
  channel's own word for a member who runs the addon, else the area the listing names for them, else "not
  placed yet". A group takes two lines: the leader and the size with where most of the group is ("2 at the
  entrance", "all inside"), and beneath, its role symbols and where the rest is ("+1 in Elwynn Forest, 2
  not placed yet"); it ranks by the members' average, and the tooltip names each member. Nearest first,
  tank before healer before dps among equals. A `~` marks a guess from an area name. A right-click invites.
  The playstyle each listing was posted with - Learning, Relaxed, Serious or Expert, in the finder's own
  words - stands dim after the name, and in the tooltip; your own listing's stands on the You line.
- **The panel docks** beside the finder window: it appears with the finder and closes with it. The X closes
  it until the finder is opened again. `/dr show` keeps it on screen on its own, `/dr dock off` leaves it
  where you put it.
- **Refresh** runs a search of its own (a click, as the client demands of that search): while the finder's
  Browse tab is open, for the finder's own filter as it stands - read, never written - and with the finder
  closed, for the picked dungeon. The finder's own refresh button is never clicked (clicked from an addon,
  its search is blocked by the client), and Blizzard's own list is never re-ordered.
- **The dungeon list is the finder's.** Its activity table names every instance of this realm - Forever's own
  included - by the instance's map id, with the finder's own suggested level range and size. Raids are left
  out: the radar is for five-man groups. An instance the finder lists in wings - the Monastery's four, Dire
  Maul's three, Stratholme's two, the two Spires: one map id under several names - has each wing as an
  option of its own under the instance, with its own range, named by its own part ("Graveyard") and tagged
  with the finder's short name (`sm gy`); the instance itself spans them and stands for all of them, so a
  search for it asks for every wing. The finder's short names are the tags everywhere they exist (`dm`,
  `hot`); the built-in table's tags hold where they do not. The dungeon
  journal adds names where this client has one. The built-in table adds tags to type, the zones, the old
  world's doors, and level ranges for Forever's nine (Hall of Thanes 13-18 ... Shaper's Terrace 58-60) until
  the finder's own numbers replace them. The list is sorted by level and coloured as the finder colours its
  own: grey once you are past a range, red while you are under it. (The finder's own dropdown hides every
  activity outside your suggested level range unless its level filter is off; the panel's list hides none.)
- **Groups and players apart.** The finder's listings come in two sections, groups first, each nearest first.
  A group shows one role symbol per member, tanks first, on its second line; a person alone the roles they
  offer, on the one line.
- **A /who for the rest.** A listing names an area for its leader only. For every other member nobody has
  placed, one who query by name rides on your next key press (the client allows the query on a key press or
  a click only), ten seconds apart, and on the Refresh click. The answer is read from the chat path and
  swallowed there, since results sent to the UI would open the finder's Who tab every time. It holds for five
  minutes; a name the who does not find is left alone for three.

## Commands

`/dr` lists them. `/dr <dungeon>` picks one; `list`, `none`, `where`, `lfg`, `refresh`, `dock on|off`,
`share on|off`, `show`, `hide`, `reset`, `diag`.

## Files

```
Core.lua         namespace, events, saved variables (one account table, a profile per character), commands
Dungeons.lua     the instances from the finder and the journal, the table's tags and seed doors, the map's pins, the learned doors, the pick
Position.lua     your spot as the client gives it, the proximity ladder, learning the door
Net.lua          the hidden channel: positions, doors and scans in and out
LFG.lua          the game's group finder, followed and read: the pick, the list sorted by proximity and role, a search
Lookup.lua       a /who by name for the listed members the finder does not place, riding on your key presses
Panel.lua        the panel
Diagnostics.lua  /dr diag
```

## What is proven, and what is not

Unproven in game as of 2026-10-16: everything - this is the first build. The channel mechanics (join from
a timer, addon messages arriving in 3-6 s) were measured on this realm on 2026-10-01 by a probe of
another addon of the family. The seed coordinates are from memory of the old world; walking in corrects
them. The client's dungeon-entrance pins may or may not exist for the old world (the report says).

MIT, by Purrdee.
