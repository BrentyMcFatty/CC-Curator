--#region Initialization stuffs...
local complete = require("cc.completion")
local strings = require("cc.strings")
local output = peripheral.find("modem").getNameLocal()
local input = peripheral.find("create:item_vault")
local spk = peripheral.find("speaker")
local history = {}
--The length of the terminal history that you can scroll through.
local historyLen = 10
local version = "0.2.8"
--#endregion

--#region errors and stuff
if not output then
  error("No output detected, this either means there is no modem present or the modem is not active.",0)
end
if not input then
  error("No vault detected, are you sure there is one nearby?",0)
end
--#endregion

--Initialise the history setting on first boot, otherwise read the existing history
if not settings.get("curator_history") then
  settings.define("curator_history", {description="The curator's terminal history.",type="table",default={}})
else
  history = settings.get("curator_history")
end



--#region functions

---Taken and modified from the Archivist, generates an autocomplete friendly list of entries.
---@param list table
---@param commands table
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

  table.sort(items, function(a, b)
    return #a < #b
  end)
  
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
local function extract(input,requests,output,blit)
  local remainder = 0
  for key, request in pairs(requests) do
    remainder = request.count - input.pushItems(output,request.slotid,request.count)
  end
  return remainder
end

local function slowWrite(text, rate)
  rate = rate or 20
  if rate < 0 then
      error("Rate must be positive", 2)
  end
  local to_sleep = 1 / rate
  local characters = rate / 20
  local text = tostring(text)

  for n = 1, #text,characters do
      sleep(to_sleep)
      if spk then
        spk.playSound("create:scroll_value",0.3,3)
      end
      write(text:sub(n, n+characters-1))
  end
end


local function printColor(text,color,bgcolor,nl)
  local oldText = term.getTextColor()
  local oldBg = term.getBackgroundColor()
  local newLine = nl and "\n" or ""
  term.setBackgroundColor(bgcolor)
  term.setTextColor(color)
  -- io.write(text..newLine)
  slowWrite(text..newLine,250)
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

local function addHistory(history,item,historyLen)
  if (not history) or (not item) then
    error("Incorrect usage")
  end
  local history = history or {}
  local historyLen = historyLen or 10
  table.insert(history,item)
  if #history > historyLen then
    table.remove(history, 1)
  end
  settings.set("curator_history", history)
  settings.save()
end


--#endregion

--#region commands
local commands = {
  ["refresh"] = function ()
    printColor("> Refreshing index...", colors.red, colors.black, true)
  end,
  ["exit"] = function ()
    printColor("> Exiting program...", colors.red, colors.black, true)
    return true
  end,
  ["count"] = function (params,list)
    local count = 0
    local result = searchItem(list, params[2],math.huge)
    for key, value in pairs(result) do
      count = count + value.count
    end
    printColor("> I have found ", colors.red, colors.black, false)
    printColor(count, colors.white, colors.black, false)
    printColor(" items with that name.", colors.red, colors.black, true)
  end,
  ["total"] = function (params,list)
    local slots = input.size() * 64
    local total = 0
    for key, value in pairs(list) do
      total = total + value.count
    end

    local percent = math.floor(((total/slots)*100)+0.5)
    printColor("> This vault has ", colors.red, colors.black, false)
    printColor(total, colors.white, colors.black, false)
    printColor(" items in total!", colors.red, colors.black, true)
    printColor("> Approximately ", colors.red, colors.black, false)
    printColor(percent.."%", colors.white, colors.black, false)
    printColor(" of the vault!", colors.red, colors.black, true)
  end,
  ["select"] = function (params,list)
    if not params[2] then return end
    if not tonumber(params[2]) then return end
    if tonumber(params[2]) > 16 then return end
    if tonumber(params[2]) < 1 then return end
    local slot = tonumber(params[2])
    turtle.select(slot)
    printColor("> Selected slot ", colors.red, colors.black, false)
    printColor("#1", colors.white, colors.black, true)
  end,
  ["commands"] = function (params,list,commands)
    printColor("> Available commands: ", colors.red, colors.black,true)
    printColor("> ", colors.red, colors.black,false)
    local commandNames = {}
    for key, value in pairs(commands) do
      commandNames[#commandNames+1] = key
    end
    printColor(table.concat(commandNames, ", "), colors.white, colors.black,true)
  end,
  ["help"] = function (params,list,commands)
    commands.commands(params,list,commands)
  end,
  ["clear"] = function (params,list,commands)
    term.clear()
    term.setCursorPos(1, 1)
  end,
  ["deposit"] = function (params,list,commands)
    if params[2] then
      if not tonumber(params[2]) then return end
      if tonumber(params[2]) > 16 then return end
      if tonumber(params[2]) < 1 then return end
    end
    local slot = tonumber(params[2]) or turtle.getSelectedSlot()
    local count = input.pullItems(output,slot)
    printColor("> ", colors.red, colors.black,false)
    printColor(count, colors.white, colors.black,false)
    printColor(" item(s) have been deposited!", colors.red, colors.black,true)
  end,
  ["forget"] = function (params,list,commands)
    history = {}
    settings.set("curator_history", {})
    settings.save()
  end,
  ["dump"] = function (params,list,commands)
    local count = 0
    for i = 1, 16 do
      count = count + input.pullItems(output,i)
    end
    printColor("> ", colors.red, colors.black,false)
    printColor(count, colors.white, colors.black,false)
    printColor(" item(s) have been dumped!", colors.red, colors.black,true)
  end,
  ["lua"] = function (params,list,commands)
    shell.run("lua")
  end,
}
--#endregion commands

local function loop()
  local itemList = input.list()
  local autocomplete = genList(itemList, commands)

  printColor("> Command/Item name?", colors.red, colors.black, true)
  printColor("> ", colors.green, colors.black, false)

  local request = read(nil, history
  ,function(text)
      if string.len(text) <= 0 then return end
      local space = string.find(text," ") or 0
      local autocompleteItems = {["count"] = true}
      local section = string.sub(text,space+1)
      if autocompleteItems[string.sub(text,0,space-1)] then
        return complete.choice(section, autocomplete)
      end
      return complete.choice(text, autocomplete)
    end
  )

  if (request == "") or (not request) then return end

  local args = splitWords(request, " ")
  if commands[args[1]] then
    addHistory(history, request, historyLen)
    return commands[args[1]](args,itemList,commands)
  elseif args[1] and tonumber(args[2]) then
    local packet, remainder = searchItem(itemList, args[1], args[2])
    addHistory(history, request, historyLen)
    local moved = args[2] - remainder
    printColor("> Extracting ", colors.red, colors.black, false)
    printColor(" "..moved, colors.white, colors.black, false)
    printColor(" item(s) from the vault!", colors.red, colors.black, true)
    extract(input, packet, output)
  else
    addHistory(history, request, historyLen)
    printColor("> Item count?", colors.red, colors.black, true)
    printColor("#> ", colors.green, colors.black, false)
    local count = tonumber(read()) or 64
    local packet, remainder = searchItem(itemList, args[1],count)
    local moved = count - remainder
    printColor("> Extracting ", colors.red, colors.black, false)
    printColor(" "..moved, colors.white, colors.black, false)
    printColor(" item(s) from the vault!", colors.red, colors.black, true)
    extract(input, packet, output)
  end
end


--#region end stuff
term.clear()
term.setCursorPos(1, 1)
if spk then
  spk.playSound("create:confirm",1,1)
end
sleep(0.5)
printColor("> My name is the Curator ", colors.red, colors.black, false)
printColor("V"..version, colors.white, colors.black, false)
printColor(", my job is to make sure you can interact with the Archivist's storage!", colors.red, colors.black, true)

printColor("> If you don't know what to do, try using ", colors.red, colors.black, false)
printColor("\"help\"", colors.white, colors.black, false)
printColor(" or ", colors.red, colors.black, false)
printColor("\"commands\"", colors.white, colors.black, false)
printColor("!", colors.red, colors.black, true)


repeat
  local exit = loop()
until exit == true

--#endregion