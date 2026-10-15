-- apColorTest: shows which drawing calls this radio really paints, so apOSD can use the right ones.
-- It cycles through 6 pages by itself (about 5 seconds each). Press Exit to quit. It only draws; it saves nothing.
-- Written without string methods (s:sub etc.) on purpose.

local PAGES = 6
local MAGENTA = nil

local function label(x, y, s)
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(200, 0, 200))
  lcd.drawText(x, y, s, (SMLSIZE or 0) + CUSTOM_COLOR)
end

local COLS = { { "dark", 10, 12, 16 }, { "black", 0, 0, 0 }, { "red", 255, 0, 0 }, { "green", 0, 160, 0 },
               { "blue", 0, 0, 255 }, { "grey", 128, 128, 128 }, { "white", 255, 255, 255 } }

local function squares(opacity)
  for i, c in ipairs(COLS) do
    lcd.setColor(CUSTOM_COLOR, lcd.RGB(c[2], c[3], c[4]))
    local x = 8 + (i - 1) * 66
    if opacity then
      lcd.drawFilledRectangle(x, 40, 60, 60, CUSTOM_COLOR, opacity)
    else
      lcd.drawFilledRectangle(x, 40, 60, 60, CUSTOM_COLOR)
    end
    label(x, 104, c[1])
  end
end

local pages = {}
pages[1] = function() squares() label(4, 4, "A: filled rects, setColor + CUSTOM_COLOR") end
pages[2] = function() squares(255) label(4, 4, "B: same, with opacity argument 255") end
pages[3] = function()
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(10, 12, 16))
  lcd.clear(CUSTOM_COLOR)
  label(4, 4, "C: lcd.clear(colour). Whole screen dark = works")
end
pages[4] = function()
  local ok, b = pcall(Bitmap.open, "/SCRIPTS/TOOLS/apOSD/bg_480x272.png")
  local w, h = 0, 0
  if ok and b then w, h = Bitmap.getSize(b) end
  if ok and b and w > 0 then lcd.drawBitmap(b, 0, 0) end
  label(4, 4, "D: picture " .. tostring(w) .. " x " .. tostring(h) .. (w > 0 and " (loaded)" or " (not loaded)"))
end
pages[5] = function()
  label(4, 4, "E: fills using the theme colour constants")
  local names = { "COLOR_THEME_PRIMARY1", "COLOR_THEME_PRIMARY2", "COLOR_THEME_SECONDARY1", "COLOR_THEME_SECONDARY2",
                  "COLOR_THEME_FOCUS", "COLOR_THEME_EDIT", "COLOR_THEME_ACTIVE", "COLOR_THEME_WARNING", "COLOR_THEME_DISABLED" }
  for i, n in ipairs(names) do
    local v = _G[n]
    local x, y = 8 + ((i - 1) % 5) * 92, 40 + math.floor((i - 1) / 5) * 80
    if v then lcd.drawFilledRectangle(x, y, 84, 56, v) end
    label(x, y + 60, v and string.sub(n, 13) or ("no " .. string.sub(n, 13)))
  end
end
pages[6] = function()
  label(4, 4, "F: outline, line and text in colours")
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(255, 0, 0)); lcd.drawRectangle(8, 40, 110, 60, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 160, 0)); lcd.drawLine(140, 40, 240, 100, SOLID or 0, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 0, 255)); lcd.drawText(260, 36, "blue text", (MIDSIZE or 0) + CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(255, 255, 255)); lcd.drawText(260, 76, "white text", (MIDSIZE or 0) + CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 0, 0)); lcd.drawText(260, 116, "black text", (MIDSIZE or 0) + CUSTOM_COLOR)
end

local function init() end

local function run(event)
  if EVT_EXIT_BREAK and event == EVT_EXIT_BREAK then return 2 end
  local page = math.floor((getTime and getTime() or 0) / 500) % PAGES + 1 -- a new page about every 5 seconds
  lcd.clear()
  local ok, err = pcall(pages[page])
  if not ok then label(4, 40, "page " .. page .. " error: " .. tostring(err)) end
  label((LCD_W or 480) - 70, (LCD_H or 272) - 18, "page " .. page .. "/" .. PAGES)
  return 0
end

return { init = init, run = run }
