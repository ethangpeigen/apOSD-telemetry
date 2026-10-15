-- apProbe4: does this radio hand raw CRSF telemetry frames to Lua (crossfireTelemetryPop)? Counts frame types.
-- Run it while the vehicle is on and linked. It only listens and draws. It saves /apProbe4.txt.
-- GPS frames (type 0x02) are only counted: their bytes would reveal the position and are never recorded.
-- Written without string methods (s:sub etc.) on purpose. Press Exit to quit.

local counts, lens, last = {}, {}, {}
local total, polls, lastSave = 0, 0, -1000
local avail = crossfireTelemetryPop ~= nil
local report = {}

local function hex(t)
  local out = {}
  for i = 1, #t do out[#out + 1] = string.format("%02X", t[i] % 256) end
  return table.concat(out, " ")
end

local function poll()
  if not avail then return end
  polls = polls + 1
  for _ = 1, 40 do
    local ok, cmd, data = pcall(crossfireTelemetryPop)
    if not ok or cmd == nil then break end
    total = total + 1
    counts[cmd] = (counts[cmd] or 0) + 1
    local n = type(data) == "table" and #data or -1
    lens[cmd] = n
    if cmd ~= 0x02 and n >= 0 and n <= 24 then last[cmd] = hex(data) end
  end
end

local function build()
  report = {}
  local function add(s) report[#report + 1] = s end
  add("LCD " .. tostring(LCD_W) .. " x " .. tostring(LCD_H))
  add("crossfireTelemetryPop: " .. (avail and "available" or "NOT available"))
  add("crossfireTelemetryPush: " .. (crossfireTelemetryPush and "available" or "NOT available"))
  add(string.format("polls: %d   frames received: %d", polls, total))
  local ids = {}
  for cmd in pairs(counts) do ids[#ids + 1] = cmd end
  table.sort(ids)
  for _, cmd in ipairs(ids) do
    local text = string.format("type 0x%02X  count %d  length %d", cmd, counts[cmd], lens[cmd])
    if cmd == 0x02 then text = text .. "  (position bytes not recorded)"
    elseif last[cmd] then text = text .. "  last: " .. last[cmd] end
    add(text)
  end
  if total == 0 then add("no frames yet (vehicle linked? wait a few seconds)") end
end

local function save()
  if not (io and io.open and io.write and io.close) then return end
  pcall(function()
    local fh = io.open("/apProbe4.txt", "w")
    if not fh then error("open failed") end
    io.write(fh, table.concat(report, "\n"), "\n")
    io.close(fh)
  end)
end

local function init() end

local function run(event)
  if EVT_EXIT_BREAK and event == EVT_EXIT_BREAK then return 2 end
  poll()
  local now = getTime and getTime() or 0
  if now - lastSave >= 200 then -- refresh the report and the file about every 2 seconds
    build()
    save()
    lastSave = now
  end
  local flags = SMLSIZE or 0
  local lh = 14
  if lcd.sizeText then
    local ok, _, hh = pcall(lcd.sizeText, "0", flags)
    if ok and hh then lh = hh + 1 end
  end
  lcd.clear()
  for i, line in ipairs(report) do
    if 2 + (i - 1) * lh > (LCD_H or 272) - lh then break end
    lcd.drawText(2, 2 + (i - 1) * lh, line, flags)
  end
  return 0
end

return { init = init, run = run }
