local crashed = settings.get("curatorCrashed", false)

--debug screen
local mon = nil
if ({ ... })[1] == "debug" then
  mon = peripheral.find("monitor")
end


if crashed then
  settings.set("curatorCrashed", false)
  settings.save()
end

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
---@diagnostic disable-next-line: param-type-mismatch
local mechDisplay = peripheral.find("create_source")
local ratu = require("RATU")
local history = {}
--The length of the terminal history that you can scroll through.
local historyLen = 10
local version = "0.4.2"
local clearDisplay = settings.get("curatorClearDisplay", false)
local smile = settings.get("curatorSmile", false)
--#endregion

--#region errors and stuff
if not output then
  error("No output detected, this either means there is no modem present or the modem is not active.", 0)
end
if not input then
  error("No vault detected, are you sure there is one nearby?", 0)
end
--#endregion

--Initialise the history setting on first boot, otherwise read the existing history
if not settings.get("curator_history") then
  settings.define("curator_history", { description = "The curator's terminal history.", type = "table", default = {} })
else
  history = settings.get("curator_history")
end



--#region functions
---Generates a mechanical display friendly list of items. sorted and size ensured!
---@param inventory ccTweaked.peripherals.Inventory The inventory used to get detailed item names.
---@param list ccTweaked.peripherals.inventory.itemList The list of items, technically unneccesary but it skips getting the item list again
---@param width integer Width of the display
---@param height integer Height of the display
---@return table result The rows table that can be printed on the display!
local function genDisplayList(inventory, list, width, height)
  local list = list or {}
  local width = width or 100
  local height = height or 100
  local counted = {}
  local sorted = {}
  local result = {}

  for key, item in pairs(list) do
    if counted[item.name] then
      counted[item.name] = { count = counted[item.name].count + item.count, slot = key }
    else
      counted[item.name] = { count = item.count, slot = key }
    end
  end

  for key, value in pairs(counted) do
    sorted[#sorted + 1] = { name = key, count = value.count, slot = value.slot }
  end

  table.sort(sorted, function(a, b)
    return a.count > b.count
  end)

  for i = 1, height do
    if sorted[i] then
      local detail = inventory.getItemDetail(sorted[i].slot) or {displayName = "error"}
      local count
      if (sorted[i].count < 1000) or (sorted[i].count >= 100000) then
        count = strings.ensure_width(tostring(sorted[i].count), 4)
      elseif (sorted[i].count < 10000) then
        count = strings.ensure_width(tostring(strings.ensure_width(tostring(sorted[i].count / 1000), 3) .. "k"), 4)
      else
        count = strings.ensure_width(tostring(strings.ensure_width(tostring(sorted[i].count / 1000), 2) .. "k"), 4)
      end
      result[i] = strings.ensure_width(count .. detail.displayName, width)
    else
      result[i] = (" "):rep(width)
    end
    sleep(0)
  end



  return result
end


---Taken and modified from the Archivist, generates a user friendly list of items for the autocomplete function.
---@param list table
---@return table autocomplete
local function genList(list)
  local modnames = {}
  local modhash = {}
  local result = {}
  local items = {}
  local itemhash = {}

  --Deduplicates the mod names and item names
  for _, v in pairs(list) do
    local _, colon = v.name:find(":")
    local modname = v.name:sub(1, colon)
    if not modhash[modname] then
      modnames[#modnames + 1] = modname
      modhash[modname] = true
    end
    if not itemhash[v.name] then
      items[#items + 1] = v.name
      itemhash[v.name] = true
    end
  end

  table.sort(items, function(a, b)
    return #a < #b
  end)
  table.sort(modnames, function(a, b)
    return #a < #b
  end)

  for i, v in pairs(modnames) do
    result[#result + 1] = v
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
local function searchItem(list, item, count)
  local requests = {}
  local remainder = tonumber(count)

  for key, value in pairs(list) do
    if value.name == item then
      local min = math.min(value.count, remainder)
      requests[#requests + 1] = { slotid = key, count = min }
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
local function extract(input, requests, output, blit)
  local remainder = 0
  for key, request in pairs(requests) do
    remainder = request.count - input.pushItems(output, request.slotid, request.count)
  end
  return remainder
end

---Helper function, splits an input into its constituent words into a table
---@param text string
---@param char string
---@return table result
local function splitWords(text, char)
  local result = {}
  for k, v in string.gmatch(text, "([^" .. char .. "]+)") do
    result[#result + 1] = k
  end
  return result
end

---Adds stuff to the terminal history
---@param history table the history table
---@param item string the item to add
---@param historyLen number maximum history length
local function addHistory(history, item, historyLen)
  if (not history) or (not item) then
    error("Incorrect usage")
  end
  local history = history or {}
  local historyLen = historyLen or 10
  if history[#history] == item then return end
  table.insert(history, item)
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
local function contains(table, element)
  for key, value in pairs(table) do
    if value == element then return true end
  end
  return false
end

---Generated by chatgpt
local function evaluateMathEquation(equation)
  -- Define a set of safe functions and variables
  local safeEnv = {
    math = math,
    tonumber = tonumber,
    tostring = tostring,
  }

  -- Create a function in the safe environment
  local safeFunction, errorMsg = load("return " .. equation, "equation", "t", safeEnv)

  -- Check for syntax errors in the equation
  if not safeFunction then
    return nil, "Syntax error: " .. errorMsg
  end

  -- Call the function and retrieve the result
  local success, result = pcall(safeFunction)

  -- Check for errors during function execution
  if not success then
    return nil, "Error: " .. result
  end

  return result
end

--#endregion


--#region commands
local commands = {
  ["help"] = {
    ["function"] = function(commands, params, itemList)
      if (params[2]) and (commands[params[2]]) and (commands[params[2]].description) then
        ratu.lengthwisePrint({ text = "&e> " .. commands[params[2]].description, spk = spk, skippable = true, length = 5, nl = true })
        if commands[params[2]].hidden then
          sleep(1)
          commands["reboot"]["function"](commands, params, itemList)
        end
        return
      end
      if (params[2] and commands[params[2]]) and (not commands[params[2]].hidden) then
        ratu.lengthwisePrint({ text = "&e> That command doesn't have a description... weird", spk = spk, skippable = true, length = 5, nl = true })
        return
      end
      commands.commands["function"](commands, params, itemList)
    end,
    ["autocomplete"] = function(commands, Itemlist)
      local result = {}
      for key, value in pairs(commands) do
        if value.description and not value.hidden then
          table.insert(result, key)
        end
      end
      return result
    end,
    ["description"] = "This command! You can use it to see what other commands do!",
  },
  ["refresh"] = {
    ["function"] = function(commands, params, list)
      ratu.lengthwisePrint({ text = "&e> Refreshing index...", spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["description"] = "Just an idle command for when the Curator should rescan the vault"
  },

  ["exit"] = {
    ["function"] = function(commands, params, list)
      ratu.lengthwisePrint({ text = "&e> Exiting program...", spk = spk, skippable = true, length = 1, nl = true })
      return true
    end,
    ["description"] = "Exits the program, self explanatory"
  },

  ["total"] = {
    ["function"] = function(commands, params, list)
      ---@diagnostic disable-next-line: undefined-field
      local slots = input.size() * 64
      local total = 0
      for key, value in pairs(list) do
        total = total + value.count
      end

      local percent = math.floor(((total / slots) * 100) + 0.5)
      ratu.lengthwisePrint({ text = "&e> This vault has &0" .. total .. " &eitems in total!", spk = spk, skippable = true, length = 5, nl = true })
      ratu.lengthwisePrint({ text = "&e> Approximately &0" .. percent .. "%% &eitems in total!", spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["description"] = "Gets a total amount of items in a vault, approximately&0*"
  },

  ["clear"] = {
    ["function"] = function(commands, params, list)
      term.clear()
      term.setCursorPos(1, 1)
      ratu.lengthwisePrint({ text = "&e> Command/Item name?", spk = spk, skippable = false, length = 5, nl = true })
    end,
    ["description"] = "Clears the terminal screen!"
  },
  ["toggleclear"] = {
    ["function"] = function(commands, params, list)
      clearDisplay = not clearDisplay
      settings.set("curatorClearDisplay", clearDisplay)
      settings.save()
      ratu.lengthwisePrint({ text = "&e> Display clear set to:&0" .. tostring(clearDisplay), spk = spk, skippable = false, length = 5, nl = true })
    end,
    ["description"] =
    "Toggles whether or not the mechanical display attacked should clear itself when updating or not. Purely cosmetic."
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
      local count = input.pullItems(output, slot)
      ratu.lengthwisePrint({ text = "&e> &0" .. count .. "&e item(s) have been deposited!", spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["autocomplete"] = function(commands, Itemlist)
      local result = {}
      for i = 1, 16 do
        table.insert(result, tostring(i))
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
      ratu.lengthwisePrint({ text = "&e> Selected slot &0" .. "#" .. slot, spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["autocomplete"] = function(commands, Itemlist)
      local result = {}
      for i = 1, 16 do
        table.insert(result, tostring(i))
      end
      return result
    end,
    ["description"] =
    "Selects the slot from the Curator's inventory, not used for much, but the selected slot is the default value for &0\"Deposit\"",
  },

  ["forget"] = {
    ["function"] = function(commands, params, list)
      history = {}
      settings.set("curator_history", {})
      settings.save()
      ratu.lengthwisePrint({ text = "&e> Like it never happened...", spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["description"] = "Clears the terminal history",
    ["autocomplete"] = function(commands, Itemlist)
      return { "me already, Jeremy?" }
    end,
  },

  ["dump"] = {
    ["function"] = function(commands, params, list)
      local count = 0
      for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
          ---@diagnostic disable-next-line: undefined-field
          count = count + input.pullItems(output, i)
        end
      end
      ratu.lengthwisePrint({ text = "&e> &0" .. count .. "&e item(s) have been dumped!", spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["description"] = "Dumps the entire internal inventory to the connected vault"
  },

  ["lua"] = {
    ["function"] = function(commands, params, list)
      shell.run("lua")
    end,
    ["description"] = "Starts the &0Lua REPL&e, useful for debugging, but not much else"
  },

  ["history"] = {
    ["function"] = function(commands, params, list)
      ratu.lengthwisePrint({ text = "&e> Terminal history:", spk = spk, skippable = true, length = 5, nl = true })
      ratu.lengthwisePrint({ text = "&e> &0" .. table.concat(history, ", "), spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["description"] = "Lists the terminal history!"
  },

  ["commands"] = {
    ["function"] = function(commands, params, list)
      ratu.lengthwisePrint({ text = "&e> Available commands:", spk = spk, skippable = true, length = 5, nl = true })
      local commandNames = {}
      for key in pairs(commands) do
        if not (commands[key].hidden) then
          commandNames[#commandNames + 1] = key
        end
      end
      ratu.lengthwisePrint({ text = "&e> &0" .. table.concat(commandNames, ", "), spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["description"] = "Lists all available commands!"
  },

  ["count"] = {
    ["function"] = function(commands, params, list)
      local count = 0
      if not params[2] then
        ratu.lengthwisePrint({ text = "&e> You must provide something to count!", spk = spk, skippable = true, length = 5, nl = true })
        return
      end
      local result = searchItem(list, params[2], math.huge)
      if #result == 0 then
        ratu.lengthwisePrint({ text = "&e> No such item, I'm afraid.", spk = spk, skippable = true, length = 5, nl = true })
        return
      end
      for key, value in pairs(result) do
        count = count + value.count
      end
      ratu.lengthwisePrint({ text = "&e> I have found &0" .. count .. "&e items with that name", spk = spk, skippable = true, length = 5, nl = true })
    end,
    ["autocomplete"] = function(commands, Itemlist)
      return Itemlist
    end,
    ["description"] = "This is to count items in a vault!"
  },
  ["ratu"] = {
    ["function"] = function(commands, params, itemList)
      ratu.lengthwisePrint({
        text = "&e> This is a brief test of a command utilising the &0RATU API&e in the curator.",
        spk = spk,
        skippable = true,
        length = 5,
        nl = true
      })
      ratu.lengthwisePrint({
        text =
        "&e> This is a really long message that prints in segments excruciatingly slowly, but is skippable!",
        spk = spk,
        skippable = true,
        length = 1,
        nl = true
      })
      ratu.wordwisePrint({
        text = "&e> This is a super long message that prints word by word, which is also skippable!",
        spk = spk,
        skippable = true,
        nl = true
      })
      ratu.lengthwisePrint({
        text = "&e> This &1is a &4demonstration &dof the RATU color &bcode system! &ahappy pride!",
        length = 5,
        spk = spk,
        skippable = false,
        nl = true
      })
    end,
    ["description"] = "Test command for the &0RATU&e api implementation.",
  },
  ["colored"] = {
    ["function"] = function(commands, params, itemList)
      ratu.lengthwisePrint({ text = "&e> Input some text and I will echo it after applying the color codes!", spk = spk, skippable = false, length = 5, nl = true })
      ratu.lengthwisePrint({ text = "&d> &0", spk = spk, skippable = false, length = 5 })
      local userInput = read()
      ratu.lengthwisePrint({ text = tostring(userInput) .. "&e &&f", spk = spk, skippable = false, length = 5, nl = true })
    end,
    ["description"] = "Have some fun with the RATU color codes!",
  },
  -- ["changelog"] = {
  --   ["function"] = function(commands, params, itemList)
  --     ratu.lengthwisePrint({ text = "&e> Version &00.4.1p&e hotfix! This is a big one.", spk = spk, skippable = true, length = 5, nl = true })
  --     os.pullEvent("key")
  --     ratu.lengthwisePrint({ text = "&e> Some minor bug fixes, as expected, stuff should now run smoother than ever!", spk = spk, skippable = true, length = 5, nl = true })
  --     os.pullEvent("key")
  --     ratu.lengthwisePrint({ text = "&e> A bit of a cool surprise", spk = spk, skippable = true, length = 5, nl = true })
  --     os.pullEvent("key")
  --   end,
  --   ["description"] = "Prints the latest changelog for the program!!",
  -- },

  ["waiting"] = {
    ["function"] = function(commands, params, itemList)
      ratu.lengthwisePrint({ text = "&&0&f aaa_b_aa_abaa_abaa abb_ab_aa_b_aa_ba_bba ababab ababab ababab &&f", spk = spk, skippable = true, length = 5, nl = true })
      commands["crash"]["function"](commands, params, itemList)
    end,
    ["description"] = "Will you?",
    ["autocomplete"] = function(commands, Itemlist)
      return { "for so long..." }
    end,
    ["hidden"] = true,
  },

  ["hidden"] = {
    ["function"] = function(commands, params, itemList)
      ratu.lengthwisePrint({
        text = "&e> Did you know that there are some commands that are &0hidden&e?",
        delay = 0.1,
        spk = spk,
        skippable = false,
        length = 5,
        nl = true
      })
      sleep(1)
      ratu.lengthwisePrint({ text = "&0 =)", spk = spk, skippable = true, length = 5, nl = true })
      sleep(1)
      commands["reboot"]["function"](commands, params, itemList)
    end,
    ["description"] = "And they might have secret descriptions too.... :3",
    ["autocomplete"] = function(commands, Itemlist)
      return { "mysteries..." }
    end,
    ["hidden"] = true,
  },
  ["reboot"] = {
    ["function"] = function(commands, params, itemList)
      os.reboot()
    end,
    ["description"] = "Reboots the Curator",
  },
  ["crash"] = {
    ["function"] = function(commands, params, itemList)
      settings.set("curatorCrashed", true)
      settings.save()
      term.setPaletteColor(colors.black, 0x040480)
      if spk then
        ---@diagnostic disable-next-line: undefined-field
        spk.playSound("watching:event.crash", 0.5, 0.7)
      end
      sleep(2)
      os.reboot()
    end,
    ["description"] = "You're not supposed to see this.",
    ["hidden"] = true,
  },
  ["search"] = {
    ["function"] = function(commands, params, itemList)
      if not (type(params[2]) == "string") then
        ratu.lengthwisePrint({
          text = "&e> Please provide a valid search term!\n&e> Usage:&0 search <searchterm>",
          spk =
              spk,
          skippable = true,
          length = 5,
          nl = true
        })
        return
      end

      local keyResults = {}
      local results = {}
      for _, itemName in pairs(itemList) do
        local colon = itemName.name:find(":")
        if itemName.name:find(params[2], colon + 1) then
          keyResults[itemName.name] = true
        end
      end

      for key, _ in pairs(keyResults) do
        results[#results + 1] = key
      end

      if #results < 1 then
        ratu.lengthwisePrint({ text = "&e> Nothing with that keyword found unfortunately!", spk = spk, skippable = true, length = 5, nl = true })
        return
      end

      local resultString = table.concat(results, ",\n")
      ratu.lengthwisePrint({ text = "&e> Search results:&0", spk = spk, skippable = true, length = 5, nl = true })
      ratu.lengthwisePrint({ text = resultString, spk = spk, skippable = true, length = 10, nl = true })
    end,
    ["description"] =
    "Search item by keyword, for those annoying items with colors in their names! Supports lua patterns but only searches the item name, not mod name",
  },
  ["duckchess"] = {
    ["function"] = function(commands, params, itemList)
      ratu.lengthwisePrint({ text = ("Duck Chess\n"):rep(25), delay = 0.1, spk = spk, skippable = false, length = 5, nl = true })
      commands["crash"]["function"](commands, params, itemList)
    end,
    ["description"] = ("Duck Chess\n"):rep(25),
    ["autocomplete"] = function(commands, Itemlist)
      return { ("Duck Chess\n"):rep(25) }
    end,
    ["hidden"] = true,
  },
}

if mechDisplay and not smile then
  commands.smile = {
    ["function"] = function(commands, params, itemList)
      local smiley = {
        "                      ",
        "         \004  \004         ",
        "         \004  \004         ",
        "                      ",
        "     \004          \004     ",
        "      \004        \004      ",
        "       \004\004\004\004\004\004\004\004       ",
        "                      ",
      }
      for i = 1, #smiley do
        mechDisplay.setCursorPos(1, i)
        mechDisplay.write(smiley[i])
      end
      sleep(3)
      settings.set("curatorSmile",true)
      settings.save()
      commands["crash"]["function"]()
    end,
    ["description"] = "You're not fully dressed without one~",
    ["autocomplete"] = function(commands, Itemlist)
      return { "like you mean it~" }
    end,
    ["hidden"] = true,
  }
end

--#endregion commands
local itemListAutocomplete
local function main()
  ---@diagnostic disable-next-line: undefined-field
  local itemList = input.list()
  itemListAutocomplete = genList(itemList)
  ratu.lengthwisePrint({ text = "&d> &0", skippable = false, length = 5, nl = false })

  local request = read(nil, history
  , function(text)
    local text = text:lower()
    if string.len(text) <= 0 then return {} end
    local space = string.find(text, " ") or 0
    local section = string.sub(text, space + 1)
    local firstElement = string.sub(text, 0, space - 1)
    if commands[firstElement] and commands[firstElement]["autocomplete"] then
      return complete.choice(section, commands[firstElement]["autocomplete"](commands, itemListAutocomplete)) or {}
    end
    local fullautocomplete = {}
    for k, v in pairs(commands) do
      if not (commands[k].hidden) then
        table.insert(fullautocomplete, k)
      end
    end
    for k, v in pairs(itemListAutocomplete) do
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
    return commands[args[1]]["function"](commands, args, itemList)
  elseif args[1] and tonumber(args[2]) then
    local count = math.ceil(args[2])
    local packet, remainder = searchItem(itemList, args[1], math.ceil(count))
    addHistory(history, request, historyLen)
    local moved = count - remainder
    ratu.lengthwisePrint({ text = "&e> Extracting &0" .. moved .. "&e item(s) from the vault!", spk = spk, skippable = true, length = 5, nl = true })
    extract(input, packet, output)
  elseif contains(itemListAutocomplete, args[1]) then
    local result
    --Count items for the dialogue
    local count = 0
    local packet, _ = searchItem(itemList, args[1], math.huge)
    for key, value in pairs(packet) do
      count = count + value.count
    end
    --
    repeat
      ratu.lengthwisePrint({ text = "&e> Item count? &0\"cancel\"&e to cancel", spk = spk, skippable = true, length = 5, nl = true })
      ratu.lengthwisePrint({ text = "&e> &0"..count.."&e items available", spk = spk, skippable = true, length = 5, nl = true })
      ratu.lengthwisePrint({ text = "&d#> &0", spk = spk, skippable = false, length = 5, nl = false })
      local userInput = read(nil, nil, function(text)
        if #text <= 0 then return { "" } end
        return complete.choice(text, { "cancel", "" }) or { "" }
      end)
      if userInput == "cancel" then return end
      result, error = evaluateMathEquation(userInput)
    until tonumber(result)

    local count = math.ceil(tonumber(result) or 0)

    addHistory(history, tostring(request .. " " .. count), historyLen)

    local packet, remainder = searchItem(itemList, args[1], count or 0)
    local moved = count - remainder

    ratu.lengthwisePrint({ text = "&e> Extracting &0" .. moved .. "&e item(s) from the vault!", spk = spk, skippable = true, length = 5, nl = true })
    extract(input, packet, output)
  else
    addHistory(history, request, historyLen)
    ratu.lengthwisePrint({ text = "&e> Unknown command or item name", spk = spk, skippable = true, length = 5, nl = true })
  end
end

--#region end stuff
term.clear()
term.setCursorPos(1, 1)
if spk then
  ---@diagnostic disable-next-line: undefined-field
  spk.playSound("create:confirm", 1, 1)
end
sleep(0.5)

local intro = [[
&e> My name is the Curator &0V]] .. version .. [[&e!
&e> My job is to make sure you can interact with the Archivist's storage!
&e> If you don't know what to do, try using &0"help"&e!
&e> Command/Item name?"
]]

if not crashed then
  ratu.lengthwisePrint({ text = intro, spk = spk, skippable = true, length = 5 })
else
  ratu.lengthwisePrint({
    text =
    "&e> It seems the Curator system has encountered corrupted data and quit unexpectedly... This incident has been reported.\n> Data expunged.",
    spk =
        spk,
    skippable = true,
    length = 5,
    nl = true
  })
end

local function updateDisplay()
  while true do sleep(60 * 60) end
end

if mechDisplay then
  function updateDisplay()
    while true do
      if clearDisplay then
        mechDisplay.clear()
      end
      local w, h = mechDisplay.getSize()
      local itemList = input.list()
      local data = genDisplayList(input, itemList, w, h)
      if mon then
        local comp = term.redirect(mon)
        term.clear()
        sleep(0.1)
        term.setCursorPos(1, 1)
        print(textutils.serialise(data))
        term.redirect(comp)
      end
      for i = 1, h do
        mechDisplay.setCursorPos(1, i)
        mechDisplay.write(data[i])
      end
      sleep(60)
    end
  end
end

local function updateIndex()
  while true do
    itemListAutocomplete = genList(input.list())
    sleep(3)
  end
end

local function mainloop()
  repeat
    local exit = main()
  until exit == true
end

parallel.waitForAny(mainloop, updateDisplay, updateIndex)

term.setPaletteColor(colors.black, 0x111111)
term.setPaletteColor(colors.red, 0xCC4C4C)

--#endregion
