--- RATU or Razvii's Advanced Terminal Utilities is effectively the frontend of Curator.
--- This library will be eventually deprecated and moved to its own repository under a different name.
--- I strongly advise NOT reading this code too much, it is not good.
local strings = require("cc.strings")
local ratu = {}

---Takes in a string and formats it using string.format() and also colors text based on color codes as described below, the values corespond to blit colors.
---@param str string string containing control codes, &[0-9a-f] for foreground color, and &&[0-9a-f] for background.
---@param nl boolean? whether to insert a newline at the end
---@param ... unknown? passthrough for string.format, any format variables in the string can be referenced here.
ratu.printColored = function(str, nl, ...)
  local str = tostring(str)
  local indices = {}
  local fstr = str:format(...)

  --#region control code findery:tm:
  local startIndex = 1
  while true do
    local start, finish, codeType
    local doubleCodeStart, doubleCodeFinish = fstr:find("&&[0-9a-f]", startIndex)
    local singleCodeStart, singleCodeFinish = fstr:find("&[0-9a-f]", startIndex)

    if doubleCodeStart and (not singleCodeStart or doubleCodeStart < singleCodeStart) then
      start, finish, codeType = doubleCodeStart, doubleCodeFinish, "bg"
    elseif singleCodeStart then
      start, finish, codeType = singleCodeStart, singleCodeFinish, "fg"
    else
      break
    end
    finish = finish or 0
    -- Add new code
    indices[#indices + 1] = { index = start, code = { codeType, fstr:sub(finish, finish) } }

    -- Remove the current color code from the string
    fstr = fstr:sub(1, start - 1) .. fstr:sub(finish + 1)
    startIndex = start
  end
  --#endregion

  --#region Splitting the string by control codes :3
  local stringTable = {}
  if #indices > 0 then
    if indices[1].index > 1 then
      local index = #stringTable + 1
      stringTable[index] = {}
      stringTable[index].str = fstr:sub(1, indices[1].index - 1)
    end
    for key, value in pairs(indices) do
      local stringEnd = indices[key + 1] and indices[key + 1].index - 1 or #fstr
      local index = #stringTable + 1
      stringTable[index] = {}
      stringTable[index].str = fstr:sub(value.index, stringEnd)
      stringTable[index].code = value.code
    end
  else
    stringTable[1] = { ["str"] = fstr }
  end
  --#endregion
  for key, value in pairs(stringTable) do
    if value.code then
      if value.code[1] == "bg" then
        term.setBackgroundColor(2 ^ tonumber("0x" .. value.code[2]))
      elseif value.code[1] == "fg" then
        term.setTextColor(2 ^ tonumber("0x" .. value.code[2]))
      end
    end
    term.write(value.str)
  end
  if nl then
    print()
  end
end

---Returns the number of RATU control codes in any given string, useful for account for the missing space in the output strings.
---@param str string the input string
---@return string count the amount of RATU control codes
ratu.countCodeChars = function(str)
  local input = str
  local count = 0
  for index in input:gmatch("&&[0-9a-f]") do
    count = count + #index
  end
  input = input:gsub("&&[0-9a-f]", "")
  for index in input:gmatch("&[0-9a-f]") do
    count = count + #index
  end
  return count
end

---The class used for wordwise print function parameters!
---@class wordwiseOptions The options table.
---@field public text string string containing control codes, &[0-9a-f] for foreground color, and &&[0-9a-f] for background.
---@field public delay number? the delay between each word printed (sleep only goes as slow as 0.025s, which is the default if not provided).
---@field public spk ccTweaked.peripherals.Speaker? the speaker object to play the ticking sound through, nil to not have it play, this uses a sound from the Create mod, you can replace it.
---@field public nl boolean? whether to newline at the end of the last segment.
---@field public skippable boolean? whether the print call can be skipped by the user by pressing any key.
---@field public varargs unknown? passthrough for string.format, any format variables in the string can be referenced here.

---Prints a given string using printColored with a delay between each word, and optionally with a ticking sound between them.
---@param options wordwiseOptions
ratu.wordwisePrint = function(options)
  assert(type(options) == "table", "Called print with nothing in it.")
  local text = tostring(options.text) or ""
  local delay = options.delay or 0.025
  local spk = options.spk or nil
  local nl = options.nl or false
  local varargs = options.varargs or nil
  local lines = strings.wrap(text, term.getSize())
  local skippable = options.skippable or false
  local skip = false
  assert(delay >= 0, "Delay cannot be negative, you can't go back in time.")

  --for all of the wrapped lines do
  for key, text in pairs(lines) do
    local words = {}
    --split the current line into words by spaces
    for value in text:gmatch("([^" .. " " .. "]+)") do
      words[#words + 1] = value
    end
    --print each word separately
    for key, word in pairs(words) do
      local space = (key == #words) and "" or " "
      ratu.printColored(word .. space, false, table.unpack(varargs or {}))
      --plays a typing sound if a speaker is provided.
      if spk and not skip then
        ---@diagnostic disable-next-line: param-type-mismatch
        spk.playSound("create:scroll_value", 0.3, 3)
      end
      if (delay > 0) and not skip then
        local timerid = os.startTimer(delay)
        local event, id
        repeat
          event, id = os.pullEvent()
        until ((event == "timer") and (id == timerid)) or (event == "key" and skippable)
        if (event == "key") and skippable then
          skip = true
          if spk then
            ---@diagnostic disable-next-line: param-type-mismatch
            spk.playSound("create:wrench_remove", 0.3, 1)
            os.queueEvent("char")
          end
        end
      end
    end
    --newline between lines unless it's the last one.
    if key ~= #lines then
      print() -- newline
    end
  end
  if nl then
    print()
  end
end

---The class used for lengthwise print function parameters, extends wordwiseOptions
---@class lengthwiseOptions: wordwiseOptions
---@field public length number the length of the segments that get written to the terminal.

---Prints a given string using printColored with a delay between each word, and optionally with a ticking sound between them.
---@param options lengthwiseOptions
ratu.lengthwisePrint = function(options)
  assert(type(options) == "table", "Called print with nothing in it.")
  local text = tostring(options.text) or ""
  local delay = options.delay or 0.025
  local spk = options.spk or nil
  local nl = options.nl or false
  local varargs = options.varargs or nil
  local length = options.length or 3
  local lines = strings.wrap(text, term.getSize())
  local skippable = options.skippable or false
  local skip = false
  assert(delay >= 0, "Delay cannot be negative, you can't go back in time.")

  for key, line in pairs(lines) do
    local segments = {}
    local startSegment = 1
    while true do
      local segment = line:sub(startSegment, startSegment + length - 1)
      --TODO fix this garbage. iterates 10 times making damn sure it doesn't cut any color code in half but man this is horrible.
      for i = 0,10 do
        if segment:sub(#segment, #segment) == "&" then
          segment = line:sub(startSegment, startSegment + length + i)
        else
          break
        end
      end
      segments[#segments + 1] = segment
      if (startSegment + length) > #line then
        break
      end
      startSegment = startSegment + #segment
    end
    for _, strs in pairs(segments) do
      ratu.printColored(strs, false, table.unpack(varargs or {}))
      --plays a typing sound if a speaker is provided.
      if spk and not skip then
        ---@diagnostic disable-next-line: param-type-mismatch
        spk.playSound("create:scroll_value", 0.3, 3)
      end
      if (delay > 0) and not skip then
        local timerid = os.startTimer(delay)
        local event, id
        repeat
          event, id = os.pullEvent()
        until ((event == "timer") and (id == timerid)) or (event == "key" and skippable)
        if (event == "key") and skippable then
          skip = true
          if spk then
            ---@diagnostic disable-next-line: param-type-mismatch
            spk.playSound("create:wrench_remove", 0.3, 1)
          end
        end
      end
    end
    if key ~= #lines then
      print() -- newline
    end
  end
  if nl then
    print() --newline
  end
end

return ratu
