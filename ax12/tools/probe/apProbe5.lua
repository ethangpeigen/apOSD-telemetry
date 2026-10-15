-- apProbe5: lists every global name this radio's Lua can see (names and kinds only, no values), to find
-- anything specific to the AX12, such as its own way to read telemetry. No vehicle is needed.
-- It saves /apProbe5.txt. Written without string methods (s:sub etc.) on purpose. Press Exit to quit.

local L = {}
local function add(s) L[#L + 1] = s end

local function listNames(items, width)
  local row = ""
  for _, item in ipairs(items) do
    if #row + #item + 1 > width then add(row) row = "" end
    row = row .. (row == "" and "" or " ") .. item
  end
  if row ~= "" then add(row) end
end

local function probe()
  local funcs, tables, consts = {}, {}, {}
  for k, v in pairs(_G) do
    local t = type(v)
    local name = tostring(k)
    if t == "function" then funcs[#funcs + 1] = name .. "()"
    elseif t == "table" then tables[#tables + 1] = name
    elseif t ~= "userdata" then consts[#consts + 1] = name end
  end
  table.sort(funcs); table.sort(tables); table.sort(consts)
  add("LCD " .. tostring(LCD_W) .. " x " .. tostring(LCD_H))
  add("-- global functions: " .. #funcs)
  listNames(funcs, 46)
  add("-- global tables: " .. #tables)
  listNames(tables, 46)
  -- the members of tables that may hold AX12-specific functions
  for _, tn in ipairs({ "model", "lcd", "io", "os", "Bitmap", "lvgl", "bit32", "debug", "package" }) do
    local t = _G[tn]
    if type(t) == "table" then
      local m = {}
      for k in pairs(t) do m[#m + 1] = tostring(k) end
      table.sort(m)
      add("-- " .. tn .. ": " .. #m)
      listNames(m, 46)
    end
  end
  add("-- constants and other values: " .. #consts .. " (first 150 names)")
  local first = {}
  for i = 1, math.min(150, #consts) do first[#first + 1] = consts[i] end
  listNames(first, 46)

  if io and io.open and io.write and io.close then
    pcall(function()
      local fh = io.open("/apProbe5.txt", "w")
      if not fh then error("open failed") end
      io.write(fh, table.concat(L, "\n"), "\n")
      io.close(fh)
    end)
  end
end

local function init()
  local ok, err = pcall(probe)
  if not ok then add("PROBE ERROR: " .. tostring(err)) end
end

local function run(event)
  if EVT_EXIT_BREAK and event == EVT_EXIT_BREAK then return 2 end
  local flags = SMLSIZE or 0
  local lh = 14
  if lcd.sizeText then
    local ok, _, hh = pcall(lcd.sizeText, "0", flags)
    if ok and hh then lh = hh + 1 end
  end
  local per = math.max(1, math.floor(((LCD_H or 272) - 4) / lh))
  local pages = math.max(1, math.ceil(#L / per))
  local page = math.floor((getTime and getTime() or 0) / 400) % pages
  lcd.clear()
  for i = 1, per do
    local line = L[page * per + i]
    if line then lcd.drawText(2, 2 + (i - 1) * lh, line, flags) end
  end
  lcd.drawText((LCD_W or 480) - 2, (LCD_H or 272) - lh, string.format("%d/%d", page + 1, pages), flags + (RIGHT or 0))
  return 0
end

return { init = init, run = run }
