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
  mgrsDigits = 5,    -- digits per axis: 5 = 1 m, 4 = 10 m, 3 = 100 m. GPS error is a few metres, so 4 also stops the last digit flickering
  background = true, -- colour radios: dimmed picture behind the OSD (bg_<W>x<H>.png next to this file)
}
