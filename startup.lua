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


---Prints in fancy colors using codes!
---@param str string string containing control codes, &[0-9a-f] for foreground color, and &&[0-9a-f] for background.
---@param nl boolean? whether to insert a newline at the end
---|true
---|false
---@param ... unknown? passthrough for string.format, any format variables in the string can be references here.
local function printColor(str,nl,...)
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

    -- Add new code
    indices[#indices + 1] = {index = start, code = {codeType, fstr:sub(finish, finish)}}

    -- Remove the current color code from the string
    fstr = fstr:sub(1, start - 1) .. fstr:sub(finish + 1)
    startIndex = start
  end
  --#endregion

  --#region Splitting the string by control codes :3
    local stringTable = {}
    if #indices > 0 then
      if indices[1].index >1 then
        local index = #stringTable+1
        stringTable[index] = {}
        stringTable[index].str = fstr:sub(1,indices[1].index-1)
      end
      for key, value in pairs(indices) do
        local stringEnd = indices[key+1] and indices[key+1].index-1 or #fstr
        local index = #stringTable+1
        stringTable[index] = {}
        stringTable[index].str = fstr:sub(value.index,stringEnd)
        stringTable[index].code = value.code
      end
    else
      stringTable[1] = {["str"] = fstr}
    end
  --#endregion
  for key, value in pairs(stringTable) do
    if value.code then
      if value.code[1] == "bg" then
        term.setBackgroundColor(2^tonumber("0x"..value.code[2]))
      elseif value.code[1] == "fg" then
        term.setTextColor(2^tonumber("0x"..value.code[2]))
      end
    end
    write(value.str)
  end
  if nl then print() end
end

local function slowWrite(text,rate,length,nl)
  
  local wrapped = strings.wrap(text,term.getSize())

  for key, lines in pairs(wrapped) do
    local segments = {}
    local startSegment = 1
    while true do
      local segment = lines:sub(startSegment,startSegment+length-1)
      if segment:sub(#segment,#segment) == "&" then
        segment = lines:sub(startSegment,startSegment+length+1)
      end
      segments[#segments+1] = segment
      if (startSegment+length) > #lines then break end
      startSegment = startSegment + #segment
    end
    for _, strs in pairs(segments) do
      printColor(strs, false)
      if spk then spk.playSound("create:scroll_value",0.3,3) end
      sleep(rate)
    end
    if key ~= #wrapped then print() end
  end
  if nl then print() end
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
  if history[#history] == item then return end
  table.insert(history,item)
  if #history > historyLen then
    table.remove(history, 1)
  end
  settings.set("curator_history", history)
  settings.save()
end

local function contains(table,element)
  for key, value in pairs(table) do
    if value == element then return true end
  end
  return false
end

--#endregion

--#region commands
local commands = {
  ["refresh"] = function ()
    slowWrite("&e> Refreshing index...", 0.025, 10,true)
  end,
  ["exit"] = function ()
    slowWrite("&e> Exiting program...", 0.025, 1,true)
    return true
  end,
  ["count"] = function (params,list)
    local count = 0
    local result = searchItem(list, params[2],math.huge)
    for key, value in pairs(result) do
      count = count + value.count
    end
    slowWrite("&e> I have found &0"..count.."&e items with that name", 0.025, 10,true)
  end,
  ["total"] = function (params,list)
    local slots = input.size() * 64
    local total = 0
    for key, value in pairs(list) do
      total = total + value.count
    end

    local percent = math.floor(((total/slots)*100)+0.5)
    slowWrite("&e> This vault has &0"..total.." items in total!", 0.025, 10,true)
    slowWrite("&e> Approximately &0"..percent.."%% &eitems in total!", 0.025, 10,true)
  end,
  ["select"] = function (params,list)
    if not params[2] then return end
    if not tonumber(params[2]) then return end
    if tonumber(params[2]) > 16 then return end
    if tonumber(params[2]) < 1 then return end
    local slot = tonumber(params[2]) or 1
    turtle.select(slot)
    slowWrite("&e> Selected slot &0".."#"..slot, 0.025, 10,true)
  end,
  ["commands"] = function (params,list,commands)
    slowWrite("&e> Available commands:", 0.025, 10,true)
    slowWrite("&e> ", 0.025, 10,false)
    local commandNames = {}
    for key, value in pairs(commands) do
      commandNames[#commandNames+1] = key
    end
    slowWrite("&0"..table.concat(commandNames, ", "), 0.025, 10,true)
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
    slowWrite("&e> &0"..count.."&e item(s) have been deposited!", 0.025, 10,true)
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
    slowWrite("&e> &0"..count.." item(s) have been dumped!", 0.025, 10,true)
  end,
  ["lua"] = function (params,list,commands)
    shell.run("lua")
  end,
  ["history"] = function (params,list,commands)
    slowWrite("&e> Terminal history:", 0.025, 10,true)
    slowWrite("&e> ", 0.025, 10,false)
    slowWrite("&0"..table.concat(history, ", "), 0.025, 10,true)
  end,
}
--#endregion commands

local function loop()
  local itemList = input.list()
  local autocomplete = genList(itemList, commands)
  slowWrite("&e> Command/Item name?",0.025, 5,true)
  slowWrite("&d> &0", 0.025, 3)

  local request = read(nil, history
  ,function(text)
      if string.len(text) <= 0 then return {} end
      local space = string.find(text," ") or 0
      local autocompleteItems = {["count"] = true}
      local section = string.sub(text,space+1)
      if autocompleteItems[string.sub(text,0,space-1)] then
        return complete.choice(section, autocomplete) or {}
      end
      return complete.choice(text, autocomplete) or {}
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
    slowWrite("&e> Extracting &0"..moved.."&e item(s) from the vault!", 0.025, 10,true)
    extract(input, packet, output)

  elseif contains(autocomplete, args[1]) then
    slowWrite("&e> Item count? \"cancel\" to cancel", 0.025, 10,true)
    slowWrite("&d#> &0", 0.025, 10,false)
    local userInput = read(nil,nil,function (text)
      if #text <= 0 then return {""} end
      return complete.choice(text,{"cancel",""}) or {""}
    end)
    if userInput == "cancel" or (not tonumber(userInput)) then return end
    local count = tonumber(userInput)
    addHistory(history, tostring(request.." "..count), historyLen)
    local packet, remainder = searchItem(itemList, args[1],count or 0)
    local moved = count - remainder
    slowWrite("&e> Extracting &0"..moved.."&e item(s) from the vault!", 0.025, 10,true)
    extract(input, packet, output)
  else
    slowWrite("&e> No such item",0.025, 3,true)
  end
end


--#region end stuff
term.clear()
term.setCursorPos(1, 1)
if spk then
  spk.playSound("create:confirm",1,1)
end
sleep(0.5)

slowWrite("&e> My name is the Curator &0V"..version.."&e!", 0.025, 15,true)
slowWrite("&e> My job is to make sure you can interact with the Archivist's storage!", 0.025, 15,true)

slowWrite("&e> If you don't know what to do, try using &0\"help\" &eor &0\"commands\"&e!", 0.025, 15,true)

repeat
  local exit = loop()
until exit == true

--#endregion