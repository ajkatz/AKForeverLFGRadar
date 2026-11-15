# AKForeverLFGRadar

## 0.1.2

- **Fixed: "Interface action failed because of an AddOn" on Refresh.** A click on Refresh sent the group
  finder's search and a /who for the next unplaced group member at the same moment; the client lets one such
  call through per click and blocked the other. Now the click only searches, and the /who goes with your
  next key press (it still rides the click when there is nothing to search).
- The family's new icon.

## 0.1.1

- **A /who only while the group finder's window is open.** The finder's last search stays readable long after
  you close it - after your group fills, too - and every key press kept asking where its unplaced members
  were. Now the questions stop the moment the window closes and start again when you open it.
- **What your group is short of comes first.** T/D/D/D puts the healers on top of the list, H/D/D/D the
  tanks - nearest first among them, then everyone else by proximity as before. Roles come from the ones
  the group assigned, else from your own listing in the finder.

## 0.1.0

- **Named AKForeverLFGRadar** (AKForeverDungeonRadar while it was being built): `/lr`, or `/dr` as before.
- **First build.** `/dr <dungeon>` picks one of the old world's instances (and Forever's own); the panel says
  how far you are from its door - `inside`, `at the entrance`, yards on the door's continent, the zone when
  the client gives no coordinates, `another continent` - and the same for everyone running the addon, who
  tell each other where they are over a hidden chat channel; their own pick shows as a tag. Doors start
  from a built-in table, take the client's own map pin when there is one, and are learned for good by the
  first addon user who walks in. A right-click invites. `/dr share off`, `/dr diag`.
- **In the game's own group finder.** The pick follows your listing and the Browse tab's filter; every listing
  for the picked dungeon - people and groups alike - comes to the panel with roles, level, class, size and
  proximity - the channel's word for addon users, the listing's own area for the rest, a group's members
  counted up - sorted by proximity and role; the panel appears beside the finder window and closes with it,
  with an X of its own; Refresh is a search of ours: the finder's own filter while its Browse tab is open (its own refresh button
  is never clicked - from an addon, its search was blocked), the picked dungeon otherwise.
  The dungeon list is the finder's activity table, Forever's own instances included, the journal added where
  the client has one; sorted by level and coloured against yours as the finder does; groups and players
  listed apart, raids left out, an instance's wings (one map id, several names) as options of their own
  under it with the finder's short names as tags, role symbols as the finder draws them, one per member of
  a group, on the group's own second line. A pick from the panel's dropdown or by command searches for it
  at once (a search of ours; the finder's own filter is never written). The playstyle a listing was posted
  with (Learning / Relaxed / Serious / Expert, the finder's own words) stands after the name, and your own
  listing's on the You line. For the members the listing does not place, a /who by name rides on your
  key presses. The panel sits clear of the finder's side tabs.
