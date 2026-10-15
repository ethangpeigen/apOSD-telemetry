-- apOSD settings. Edit and save; the script reads this file when the telemetry screen loads.
return {
  imperial  = false, -- false: km/h and m     true: mph and ft
  cells     = 0,     -- battery cell count; 0 = guess from the first voltage reading
  cellWarn  = 3.50,  -- volts per cell: yellow
  cellCrit  = 3.30,  -- volts per cell: red, flashing, beeps
  minSats   = 6,     -- satellites needed before home is recorded
  showAlt   = false, -- show altitude above home (usually off for a rover)
  horizon   = false, -- draw an artificial horizon from Ptch / Roll
  armSwitch = "",    -- optional radio switch that tracks arming, e.g. "sf" or "ls1" (armed when > 0).
                     -- Only used when the FM '*' marker is off (see README, RC_OPTIONS bit 12).
  beeps     = true,  -- tones on arm / disarm and on critical battery
  mgrs      = true,  -- show the position as an MGRS grid reference (on the small screens ENTER swaps it with current / mAh)
  mgrsDigits = 3,    -- the log's position is rounded (about 100 m): 3 = 100 m. With real sensors use 5 (1 m) or 4 (10 m).    -- digits per axis: 5 = 1 m, 4 = 10 m, 3 = 100 m. GPS error is a few metres, so 4 also stops the last digit flickering
  source    = "log",   -- "log": read the app's own log file (the AX12 app gives Lua no telemetry); "link": normal sensors
  logFile   = "",      -- log source: a fixed file such as "/2026_10_15.txt" to replay; empty = today's file
  maxAge    = 8,       -- log source: seconds without a new line before it counts as no telemetry
  mapZoom   = 16,      -- map page (press Enter): starting zoom; Up / Down change it. Tiles come from tools/make_map.py
  mapDir    = "/mp/",   -- map tiles folder (short path: this radio failed to open a 36-character one)
  mapMin    = 12,      -- lowest and highest zoom that your tile pack contains (Up / Down stop here)
  mapMax    = 16,
  mapTrail  = true,    -- map page: draw the path travelled
  theme     = "dark",  -- "dark": own dark background (+ picture if it loads); "light": dark text on the radio's pale screen
  background = true, -- dark theme only: dimmed picture behind the OSD (bg_<W>x<H>.png next to this file)
}
