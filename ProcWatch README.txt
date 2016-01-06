ProcWatch 1.0
3/21/05

This AddOn is intended to determine the proc rates of weapon procs.
It can also be used to watch for events in combat but the primary
purpose is focused on procs.

Once installed, set up a key binding in-game to Toggle ProcWatch.
Or you can enter /procwatch to summon the mod.

Everything should be self explanitory on the screen.

How it works:
- Before you type in an event to watch, it stays in an inert
  Stopped mode.
- After you type in an event, it will go into Idle mode and wait
  for you to hit a mob.
- When you hit a mob, it will go into Active mode and begin watching
  all combat spam.  When it detects the event you defined, it makes
  a note to itself.
- When you leave combat, it stops watching combat spam, totals the
  last fight you just left, adds it to the totals and goes back into Idle mode.
 

Tips:
- Wildcards can be used for a proc event. The most common are (.+) for any
  number of any characters, (%w+) for any number of alphanumeric characters,
  and (%d+) for any number of digits.  Any standard lua pattern should work.
- You can watch the procs of groupmates if their procs cause combat spam.
  For this you may want to turn on Watch All Combat.  The procs per minute
  will be the only meaningful result, since the hits will always be your hits.
- Try to keep the event as detailed as possible.  For instance if two casters
  in the group are wielding a Blood-etched blade, a "gain 120 mana" event will
  fire for either caster's proc.  You want "You gain 120 mana" instead.  If in
  doubt, turn on Notify On Proc and you'll see exactly the event that
  triggered the proc.
- Unfortunately some effects like Icy Chill are totally anonymous.  The only
  combat spam that occurs is "Target is afflicted by Chilled."  If everyone in
  the group has an icy chill proc, there's no way anyone can know who caused
  the proc.  Even a mage defensive buff procs with the exact text. For effects
  like icy chill you'll need to test in controlled situations.
- You can only pause ProcWatch during Idle mode.  If you're in Active mode and
  you want to pause, you may also want to remove the last fight from the totals
  if you didn't want to include that fight.
- Slash commands are not needed, but a few are available: /procwatch alone will
  pull up the mod. /procwatch hide will dismiss the window. /procwatch exit
  will go into a Stopped state. /procwatch followed by other text will assume
  you want to start a new watch for an event with that text.
  ie, /procwatch Your Fiery Weapon
- If you want to run procwatch as the result of some action within a macro
  script, you can also use ProcWatch_Startup("event").
  ie: /script if UnitExists("target") and UnitName("target")=="Crimson Priest" then ProcWatch_Startup("Your Feedback"); end;
- By default, the window will be movable and hide when you hit ESCape.  You
  can push the 'pin' in the titlebar to stick it in place.
- The standard close (X) in the upper right of the window will only dismiss the
  window, as if you toggled the window away or hit ESC.  It will still run as if
  it were visible.  If you want to stop monitoring completely use Exit in the
  options panel.

Note:
- This was written with the assumption that it would be used infrequently.
  If ProcWatch is stopped or paused for any reason, it will not be watching
  combat spam at all.  A primary design goal was to be as little impact as
  possible so it can remain installed and only running when the user wants it.
- That said, this mod also remembers its last state and if it's not paused or
  stopped, it will dutifully fire back up into idle mode in the next session
  and wait for a first hit if you do not Exit.

- Gello, Hyjal
