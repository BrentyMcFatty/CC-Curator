--#region Requires!
local complete = require("cc.completion")
local output = peripheral.find("modem").getNameLocal()
---@diagnostic disable-next-line: param-type-mismatch
local input = peripheral.find("create:item_vault")
--#endregion

--#region errors and stuff
if not output then
  error("No output detected, this either means there is no modem present or the modem is not active.",0)
end
if not input then
  error("No vault detected, are you sure there is one nearby?",0)
end
--#endregion

--#region functions

---Taken and modified from the Archivist, generates an autocomplete friendly list of entries.
---@param list table
---@return table autocomplete
local function genList(list,commands)
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
  for v,_ in pairs(commands) do
    table.insert(result, v)
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

---Helper function, splits an input into its constituent words
---@param text string
---@param char string
---@return table result 
local function splitWords(text,char)
  local result = {}
  for k,v in string.gmatch(text,"([^"..char.."]+)") do
    result[#result+1] = k
  end
  return result
end

--#endregion

--#region commands
local commands = {
  ["refresh"] = function (params)
    return false
  end,
  ["print"] = function (params)
    if params[2] then
      print(params[2])
    end
  end,
  ["exit"] = function (params)
    return true
  end,
  ["count"] = function (params,list)
    local count = 0
    local result = searchItem(list, params[2],math.huge)
    for key, value in pairs(result) do
      count = count + value.count
    end
    print(count)
  end,
  ["total"] = function (params,list)
    local total = 0
    for key, value in pairs(list) do
      total = total + value.count
    end
    print(total)
  end
}
--#endregion commands

local function loop()
  local itemList = input.list()
  local autocomplete = genList(itemList, commands)

  printColor("> Command/Item name?", colors.red, colors.black, true)
  printColor("> ", colors.green, colors.black, false)

  local request = read(nil, {},
    function(text) if string.len(text) > 0 then return complete.choice(text, autocomplete) else return { "" } end end)
  local args = splitWords(request, " ")
  if commands[args[1]] then
    return commands[args[1]](args,itemList)
  elseif args[1] and tonumber(args[2]) then
    local packet, remainder = searchItem(itemList, args[1], args[2])
    extract(input, packet, output)
  else
    printColor("> Item count?", colors.red, colors.black, true)
    printColor("> ", colors.green, colors.black, false)
    local count = tonumber(read()) or 64
    local packet, remainder = searchItem(itemList, args[1],count)
    extract(input, packet, output)
  end
end


--#region end stuff
printColor("> My name is the Curator V0.1, my job is to make sure you can interact with the Archivist's storage!", colors.red, colors.black, true)
repeat
  local exit = loop()
until exit == true


term.setTextColor(colors.red)
textutils.slowPrint("> Exiting...")
term.setTextColor(colors.white)
--#endregion