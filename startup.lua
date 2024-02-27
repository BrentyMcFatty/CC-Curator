term.setPaletteColor(colors.black, 0)
term.setPaletteColour(colors.red, 0xd22b2b)
--#region Initialization stuffs...
local complete = require("cc.completion")
local strings = require("cc.strings")
---@diagnostic disable-next-line: undefined-field
local output = peripheral.find("modem").getNameLocal()
---@diagnostic disable-next-line: param-type-mismatch
local input = peripheral.find("create:item_vault")
local spk = peripheral.find("speaker")
local history = {}
--The length of the terminal history that you can scroll through.
local historyLen = 10
local version = "0.3.0"
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

---Taken and modified from the Archivist, generates a user friendly list of items for the autocomplete function.
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

  table.sort(items, function(a, b)
    return #a < #b
  end)
  
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
    finish = finish or 0
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


---Slowly writes a string on the screen using the printColor function chunk by chunk
---@param text string string containing color codes
---@param rate number the amount of time between chunks
---@param length number length of chunks
---@param nl? boolean new line?
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
      ---@diagnostic disable-next-line: undefined-field
      if spk then spk.playSound("create:scroll_value",0.3,3) end
      sleep(rate)
    end
    if key ~= #wrapped then print() end
  end
  if nl then print() end
end

---Helper function, splits an input into its constituent words into a table
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

---Adds stuff to the terminal history
---@param history table the history table
---@param item string the item to add
---@param historyLen number maximum history length
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

---Checks whether element is contained within table
---@param table table
---@param element any
---@return boolean
local function contains(table,element)
  for key, value in pairs(table) do
    if value == element then return true end
  end
  return false
end

--#endregion

--#region commands

---Helps enumerate the command names
---@param commands table
---@return table result
local function getCommandList(commands)
  local result = {}
  for k,v in pairs(commands) do
    result[#result+1] = k
  end
  return result
end

local commands = {
  ["help"] = {
    ["function"] = function (commands,params,itemList)
      if (params[2]) and (commands[params[2]]) and (commands[params[2]].description) then
        slowWrite("&e> "..commands[params[2]].description,0.025, 5,true)
        return
      end
      if params[2] and commands[params[2]] then
        slowWrite("&e> That command doesn't have a description... weird",0.025, 5,true)
        return
      end
    commands.commands["function"](commands,params,itemList)
    end,
    ["autocomplete"] = function (commands,Itemlist)
      local result = {}
      for key,value in pairs(commands) do
        if value.description then
          table.insert(result, key)
        end
      end
      return result
    end,
    ["description"] = "This command! You can use it to see what other commands do!",
  },

  ["refresh"] = {
    ["function"] = function(commands, params, list)
      slowWrite("&e> Refreshing index...", 0.025, 10, true)
    end,
    ["description"] = "Just an idle command for when the computer should rescan the vault"
  },

  ["exit"] = {
    ["function"] = function(commands, params, list)
      slowWrite("&e> Exiting program...", 0.025, 1, true)
      return true
    end,
    ["description"] = "Exits the program, self explanatory"
  },

  ["total"] = {
    ["function"] = function (commands,params,list)
---@diagnostic disable-next-line: undefined-field
      local slots = input.size() * 64
      local total = 0
      for key, value in pairs(list) do
        total = total + value.count
      end
  
      local percent = math.floor(((total/slots)*100)+0.5)
      slowWrite("&e> This vault has &0"..total.." &eitems in total!", 0.025, 10,true)
      slowWrite("&e> Approximately &0"..percent.."%% &eitems in total!", 0.025, 10,true)
    end,
    ["description"] = "Gets a total amount of items in a vault, approximately"
  },

  ["clear"] = {
    ["function"] = function(commands, params, list)
      term.clear()
      term.setCursorPos(1, 1)
    end,
    ["description"] = "Clears the terminal screen!"
  },

  ["deposit"] = {
    ["function"] = function(commands, params, list)
      if params[2] then
        if not tonumber(params[2]) then return end
        if tonumber(params[2]) > 16 then return end
        if tonumber(params[2]) < 1 then return end
      end
      local slot = tonumber(params[2]) or turtle.getSelectedSlot()
---@diagnostic disable-next-line: undefined-field
      local count = input.pullItems(output,slot)
      slowWrite("&e> &0"..count.."&e item(s) have been deposited!", 0.025, 10,true)
    end,
    ["autocomplete"] = function(commands, Itemlist)
      local result = {}
      for i = 1, 16 do
        table.insert(result,tostring(i))
      end
      return result
    end,
    ["description"] = "Deposits the specified items into the vault!"
  },

  ["select"] = {
    ["function"] = function(commands, params, list)
      if not params[2] then return end
      if not tonumber(params[2]) then return end
      if tonumber(params[2]) > 16 then return end
      if tonumber(params[2]) < 1 then return end
      local slot = tonumber(params[2]) or 1
      turtle.select(slot)
      slowWrite("&e> Selected slot &0".."#"..slot, 0.025, 10,true)
    end,
    ["autocomplete"] = function(commands, Itemlist)
      local result = {}
      for i = 1, 16 do
        table.insert(result,tostring(i))
      end
      return result
    end,
    ["description"] = "Selects the slot from the Curator's inventory, not used for much, but the selected slot is the default value for &0\"Deposit\""
  },

  ["forget"] = {
    ["function"] = function(commands, params, list)
      history = {}
      settings.set("curator_history", {})
      settings.save()
    end,
    ["description"] = "Clears the terminal history"
  },

  ["dump"] = {
    ["function"] = function(commands, params, list)
      local count = 0
      for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
          ---@diagnostic disable-next-line: undefined-field
          count = count + input.pullItems(output,i)
        end
      end
      slowWrite("&e> &0"..count.." item(s) have been dumped!", 0.025, 10,true)
    end,
    ["description"] = "Dumps the entire internal inventory to the connected vault"
  },

  ["lua"] = {
    ["function"] = function(commands, params, list)
      shell.run("lua")
    end,
    ["description"] = "Starts the Lua REPL, useful for debugging, but not much else"
  },

  ["history"] = {
    ["function"] = function(commands, params, list)
      slowWrite("&e> Terminal history:", 0.025, 10,true)
      slowWrite("&e> &0"..table.concat(history, ", "), 0.025, 10,true)
    end,
    ["description"] = "Lists the terminal history!"
  },

  ["commands"] = {
    ["function"] = function(commands, params, list)
      slowWrite("&e> Available commands:", 0.025, 10,true)
      slowWrite("&e> ", 0.025, 10,false)
      local commandNames = {}
      for key in pairs(commands) do
        commandNames[#commandNames+1] = key
      end
      slowWrite("&0"..table.concat(commandNames, ", "), 0.025, 10,true)
    end,
    ["description"] = "This is to count items in a vault!"
  },

  ["count"] = {
    ["function"] = function(commands, params, list)
      local count = 0
      if not params[2] then
        slowWrite("&e> You must provide something to count!", 0.025, 10, true)
        return
      end
      local result = searchItem(list, params[2], math.huge)
      if #result == 0 then
        slowWrite("&e> No such item, I'm afraid.", 0.025, 10, true)
        return
      end
      for key, value in pairs(result) do
        count = count + value.count
      end
      slowWrite("&e> I have found &0" .. count .. "&e items with that name", 0.025, 10, true)
    end,
    ["autocomplete"] = function(commands, Itemlist)
      return Itemlist
    end,
    ["description"] = "This is to count items in a vault!"
  },


}
--#endregion commands

local function loop()
---@diagnostic disable-next-line: undefined-field
  local itemList = input.list()
  local itemListAutocomplete = genList(itemList)
  slowWrite("&e> Command/Item name?",0.025, 5,true)
  slowWrite("&d> &0", 0.025, 3)

  local request = read(nil, history
  ,function(text)
      local text = text:lower()
      if string.len(text) <= 0 then return {} end
      local space = string.find(text," ") or 0
      local section = string.sub(text,space+1)
      local firstElement = string.sub(text,0,space-1)
      if commands[firstElement] and commands[firstElement]["autocomplete"] then
        return complete.choice(section, commands[firstElement]["autocomplete"](commands,itemListAutocomplete)) or {}
      end
      if (#complete.choice(firstElement, getCommandList(commands)) > 0) and (#firstElement >= 3) and (space ~= 0) then
        local completeCommand = firstElement..complete.choice(firstElement, getCommandList(commands))[1]
        return complete.choice(section, commands[completeCommand]["autocomplete"](commands,itemListAutocomplete)) or {}
      end
      local fullautocomplete = {}
      for k,v in pairs(commands) do
        table.insert(fullautocomplete, k)
      end
      for k,v in pairs(itemListAutocomplete) do
        table.insert(fullautocomplete, v)
      end
      return complete.choice(text, fullautocomplete) or {}
    end
  ) or ""
  
  request = request:lower()

  if (request == "") then return end

  local args = splitWords(request, " ")
  if commands[args[1]] then
    addHistory(history, request, historyLen)
    return commands[args[1]]["function"](commands,args,itemList)
  elseif args[1] and tonumber(args[2]) then
    
    local packet, remainder = searchItem(itemList, args[1], args[2])
    addHistory(history, request, historyLen)
    local moved = args[2] - remainder
    slowWrite("&e> Extracting &0"..moved.."&e item(s) from the vault!", 0.025, 10,true)
    extract(input, packet, output)

  elseif contains(itemListAutocomplete, args[1]) then
    local userInput
    repeat
    slowWrite("&e> Item count? \"cancel\" to cancel", 0.025, 10,true)
    slowWrite("&d#> &0", 0.025, 10,false)
      userInput = read(nil,nil,function (text)
        if #text <= 0 then return {""} end
        return complete.choice(text,{"cancel",""}) or {""}
      end)
      if userInput == "cancel" then return end
    until tonumber(userInput)
    local count = tonumber(userInput)
    addHistory(history, tostring(request.." "..count), historyLen)
    local packet, remainder = searchItem(itemList, args[1],count or 0)
    local moved = count - remainder
    slowWrite("&e> Extracting &0"..moved.."&e item(s) from the vault!", 0.025, 10,true)
    extract(input, packet, output)
  elseif (#complete.choice(args[1], getCommandList(commands)) > 0) and (#args[1] >= 3) then
    local comm = args[1]..complete.choice(args[1], getCommandList(commands))[1]
    addHistory(history, comm, historyLen)
    return commands[comm]["function"](commands,args,itemList)
  else
    slowWrite("&e> Unknown command or item name",0.025, 10,true)
  end
end


--#region end stuff
term.clear()
term.setCursorPos(1, 1)
if spk then
---@diagnostic disable-next-line: undefined-field
  spk.playSound("create:confirm",1,1)
end
sleep(0.5)

slowWrite("&e> My name is the Curator &0V"..version.."&e!", 0.025, 15,true)
slowWrite("&e> My job is to make sure you can interact with the Archivist's storage!", 0.025, 15,true)

slowWrite("&e> If you don't know what to do, try using &0\"help\"&e!", 0.025, 15,true)
repeat
  local exit = loop()
until exit == true

term.setPaletteColor(colors.black, 0x111111)
term.setPaletteColor(colors.red, 0xCC4C4C)

--#endregion