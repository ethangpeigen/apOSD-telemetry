-- apProbe: reports what this radio's Lua can do, so apOSD can be adapted to it. (v2: also lists every telemetry name it can see)
-- It only reads and draws. It saves a short text report (no GPS position) as /apProbe.txt if the radio
-- lets scripts write files. Press EXIT to quit. Written without string methods (s:sub etc.) on purpose.

local L = {}
local wrote = ""

local function add(s) L[#L + 1] = s end
local function yn(name, v) add(string.format("%-22s %s", name, v ~= nil and v ~= false and "yes" or "NO")) end

local function describe(v)
  local t = type(v)
  if t == "table" then return "table, has lat/lon: " .. tostring(v.lat ~= nil and v.lon ~= nil) end -- values left out on purpose
  if t == "number" then return string.format("%.3f", v) end
  return t .. " " .. tostring(v)
end

local function probe()
  add("LCD " .. tostring(LCD_W) .. " x " .. tostring(LCD_H))
  if getVersion then
    local ver, radio, maj, min, rev, os = getVersion()
    add("version: " .. tostring(ver) .. " | " .. tostring(radio) .. " | " .. tostring(os))
    add("maj.min.rev: " .. tostring(maj) .. "." .. tostring(min) .. "." .. tostring(rev))
  else
    add("getVersion: NO")
  end

  add("-- functions and constants")
  yn("lcd.RGB", lcd and lcd.RGB)
  yn("lcd.setColor", lcd and lcd.setColor)
  yn("lcd.sizeText", lcd and lcd.sizeText)
  yn("lcd.drawText", lcd and lcd.drawText)
  yn("lcd.drawLine", lcd and lcd.drawLine)
  yn("lcd.drawFilledRect", lcd and lcd.drawFilledRectangle)
  yn("lcd.drawRectangle", lcd and lcd.drawRectangle)
  yn("lcd.drawBitmap", lcd and lcd.drawBitmap)
  yn("lcd.clear", lcd and lcd.clear)
  yn("Bitmap.open", Bitmap and Bitmap.open)
  yn("loadScript", loadScript)
  yn("getFieldInfo", getFieldInfo)
  yn("getRSSI", getRSSI)
  yn("getTime", getTime)
  yn("playTone", playTone)
  yn("collectgarbage", collectgarbage)
  yn("pcall", pcall)
  yn("math.atan2", math.atan2)
  yn("io.open / io.write", io and io.open and io.write)
  yn("CUSTOM_COLOR", CUSTOM_COLOR)
  yn("SMLSIZE/MIDSIZE/DBLSIZE", SMLSIZE and MIDSIZE and DBLSIZE)
  yn("EVT_VIRTUAL_ENTER", EVT_VIRTUAL_ENTER)
  yn("EVT_ENTER_BREAK", EVT_ENTER_BREAK)
  yn("EVT_EXIT_BREAK", EVT_EXIT_BREAK)
  local ok = pcall(function() return ("x"):sub(1, 1) end)
  add("string methods s:sub(): " .. (ok and "yes" or "NO (use string.sub)"))

  if lcd and lcd.sizeText then
    add("-- text sizes (width x height of a '0')")
    for _, p in ipairs({ { "small", SMLSIZE }, { "std", 0 }, { "mid", MIDSIZE }, { "dbl", DBLSIZE }, { "xxl", XXLSIZE } }) do
      if p[2] then
        local ok2, w, h = pcall(lcd.sizeText, "0", p[2])
        add(string.format("%-6s %s", p[1], ok2 and (tostring(w) .. " x " .. tostring(h)) or "error"))
      end
    end
  end

  add("-- telemetry (values only, GPS position not recorded)")
  add("getRSSI: " .. (getRSSI and tostring((getRSSI())) or "NO"))
  local private = { GPS = true, gps = true, lat = true, lng = true, lon = true, latitude = true, longitude = true }
  for _, n in ipairs({ "RxBt", "Curr", "Capa", "Bat%", "GPS", "Sats", "GSpd", "Alt", "Yaw", "Ptch", "Roll", "FM", "RQly", "1RSS", "TPWR", "Hdg", "tx-voltage",
                       "voltage", "current", "lat", "lng", "pitch", "roll", "yaw", "speed", "alt", "sats", "mode", "gps", "heading", "rssi", "lq", "battery", "fuel" }) do
    local f = getFieldInfo and getFieldInfo(n)
    local okv, v = pcall(getValue, n)
    local text = "error"
    if okv then text = private[n] and ("(" .. type(v) .. ", value not recorded)") or describe(v) end
    add(string.format("%-10s %-5s %s", n, f and "found" or "none", text))
  end

  -- every name the Lua can see, so we learn how THIS radio names its telemetry (names only, no values)
  add("-- all source names visible to Lua")
  local names, seen = {}, {}
  if getFieldInfo then
    for id = 0, 1500 do
      local okf, f = pcall(getFieldInfo, id)
      if okf and type(f) == "table" and f.name and not seen[f.name] then
        seen[f.name] = true
        names[#names + 1] = f.name
      end
    end
  end
  add("count: " .. #names)
  local row = ""
  for _, nm in ipairs(names) do
    if #row + #nm + 1 > 44 then add(row) row = "" end
    row = row .. (row == "" and "" or " ") .. nm
  end
  if row ~= "" then add(row) end

  add("-- loading and drawing")
  local f, e = loadScript("/SCRIPTS/TOOLS/apProbe.lua")
  add("loadScript own path: " .. (type(f) == "function" and "works" or ("FAILS: " .. tostring(e))))
  local okc = pcall(function()
    lcd.setColor(CUSTOM_COLOR, lcd.RGB(255, 0, 0))
    lcd.drawFilledRectangle(0, 0, 1, 1, CUSTOM_COLOR)
  end)
  add("colour drawing: " .. (okc and "works" or "FAILS"))

  -- try to save the report; the radio may or may not allow file writing
  if io and io.open and io.write and io.close then
    for _, path in ipairs({ "/apProbe.txt", "/SCRIPTS/apProbe.txt" }) do
      local okw = pcall(function()
        local fh = io.open(path, "w")
        if not fh then error("open failed") end
        io.write(fh, table.concat(L, "\n"), "\n")
        io.close(fh)
      end)
      if okw then wrote = path break end
    end
  end
  add("report file: " .. (wrote ~= "" and wrote or "not written (read the screen)"))
end

local function init()
  local ok, err = pcall(probe)
  if not ok then add("PROBE ERROR: " .. tostring(err)) end
end

local function run(event)
  if EVT_EXIT_BREAK and event == EVT_EXIT_BREAK then return 2 end
  local w, h = LCD_W or 128, LCD_H or 64
  local flags = SMLSIZE or 0
  local lh = 14
  if lcd.sizeText then
    local ok, _, hh = pcall(lcd.sizeText, "0", flags)
    if ok and hh then lh = hh + 1 end
  end
  local per = math.max(1, math.floor((h - 4) / lh))
  local pages = math.max(1, math.ceil(#L / per))
  local page = math.floor((getTime and getTime() or 0) / 400) % pages -- changes page every 4 s
  lcd.clear()
  for i = 1, per do
    local line = L[page * per + i]
    if line then lcd.drawText(2, 2 + (i - 1) * lh, line, flags) end
  end
  lcd.drawText(w - 2, h - lh, string.format("%d/%d", page + 1, pages), flags + (RIGHT or 0))
  return 0
end

return { init = init, run = run }
