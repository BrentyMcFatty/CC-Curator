local complete = require("cc.completion")
local output = peripheral.call("bottom","getNameLocal")
---@diagnostic disable-next-line: param-type-mismatch
local input = peripheral.find("create:item_vault")

if not input then
  error("No inventory detected...",2)
end
term.clear()
term.setCursorPos(1, 1)
---Taken and modified from the Archivist, generates an autocomplete friendly list of entries.
---@param list table
---@return table autocomplete
local function genList(list)
  local modnames = {}
  local modhash = {}
  local result = {}
  local items = {}
  local itemhash = {}

  for _, v in pairs(list) do
    local _, colon = v.name:find(":")
    local modname = v.name:sub(1, colon)

    if not modhash[modname] then
      modnames[#modnames + 1] = modname
      modhash[modname] = true
      result[#result+1] = modname
    end
    if not itemhash[v.name] then
      items[#items + 1] = v.name
      itemhash[v.name] = true
    end
  end

  for i, v in pairs(items) do
    result[#result + 1] = v
  end

  return result
end

---Generates a list of items that must be moved in order to satisfy the user's request, not the full IRP protocol
---@param list table
---@param item string
---@param count number
---@return table item_list The list of items that need to be moved
---@return number? remainder The remainder in case there were not enough items to satisfy the request
local function searchItem(list,item,count)
  local requests = {}
  local remainder = tonumber(count)

  for key, value in pairs(list) do
    if value.name == item then
      local min = math.min(value.count,remainder)
      requests[#requests+1] = {slotid = key,count=min}
      remainder = remainder - min
    end
    if remainder <= 0 then
      break
    end
  end
  return requests, remainder
end


---Takes in an Item Transfer Request:tm: list and transfers that list from the input to the output.
---@param input table input aka the vault to extract from
---@param requests table the requests to process
---@param output string the inventory to extract to
---@return number remainder the remaining items that were not transferred for whatever reason(IE not enough items in inventory or output full)
local function extract(input,requests,output)
  local remainder = 0
  for key, request in pairs(requests) do
    remainder = request.count - input.pushItems(output,request.slotid,request.count)
  end
  return remainder
end

local function printColor(text,color,bgcolor,nl)
  local oldText = term.getTextColor()
  local oldBg = term.getBackgroundColor()
  local newLine = nl and "\n" or ""
  term.setBackgroundColor(bgcolor)
  term.setTextColor(color)
  io.write(text..newLine)
  term.setBackgroundColor(oldBg)
  term.setTextColor(oldText)
end

local function loop()
  local list = input.list()
  local autocomplete = genList(list)
  autocomplete[#autocomplete+1] = "refresh"
  autocomplete[#autocomplete+1] = "exit"
  printColor("> Command/Item name?", colors.red, colors.black, true)
  printColor("> ", colors.green, colors.black, false)
  local search = read(nil, nil, function(text) if string.len(text) > 0 then return complete.choice(text, autocomplete) else return {""} end end)
  if search == "refresh" then
    printColor("> Refreshing index...", colors.red, colors.black, true)
    sleep(0.5)
    return
  elseif search == "exit" then
    return true
  end
  local count
  repeat
    printColor("> How many?", colors.red, colors.black, true)
    printColor("> ", colors.green, colors.black, false)
    count = read()
  until tonumber(count)

  local packet, remainder = searchItem(list, search, count)

  local found = count - remainder

  if #packet <= 0 then
    printColor("> Sorry, couldn't find that...", colors.red, colors.black, true)
    return
  end
  extract(input, packet, output)
  if remainder > 0 then
    printColor("> Extracting... I could only find: " .. found, colors.red, colors.black, true)
  else
    printColor("> Extracting items.", colors.red, colors.black, true)
  end
  sleep(0.1)
end

printColor("> My name is the Curator V0.1, my job is to make sure you can interact with the Archivist's storage!", colors.red, colors.black, true)

repeat
  local exit = loop()
until exit == true


term.setTextColor(colors.red)
textutils.slowPrint("> Exiting...")
term.setTextColor(colors.white)