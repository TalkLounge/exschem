-- mods/exschem/init.lua
-- =================
-- See README.md for licensing and other information.

exschem = {}
local exschem_ids = {}
local exschem_time = {}
local exschem_callback = {}
local chatcommand_data = {}

local function posIterator(pos1, pos2, part)
	local pos
	return function()
		if not pos then
			pos = {x = pos1.x, y = pos1.y, z = pos1.z}
		else
			pos.x = pos.x + part
			if pos.x > pos2.x then
				pos.x = pos1.x
				pos.z = pos.z + part
				if pos.z > pos2.z then
					pos.z = pos1.z
					pos.y = pos.y + part
					if pos.y > pos2.y then
						pos = nil
					end
				end
			end
		end
		return pos
	end
end

local function sort_pos(pos1, pos2)
	return {x = pos1.x < pos2.x and pos1.x or pos2.x, y = pos1.y < pos2.y and pos1.y or pos2.y, z = pos1.z < pos2.z and pos1.z or pos2.z}, {x = pos1.x > pos2.x and pos1.x or pos2.x, y = pos1.y > pos2.y and pos1.y or pos2.y, z = pos1.z > pos2.z and pos1.z or pos2.z}
end

local function exschem_return(id, errcode, err)
	if type(exschem_callback[id]) == "function" then
		exschem_callback[id](id, os.time() - exschem_time[id], errcode, err)
	end
	table.remove(exschem_ids, id)
	table.remove(exschem_time, id)
	table.remove(exschem_callback, id)
end

local function exschem_save(pos1, pos2, use_worldedit, part, filepath, delay, id, iterator)
	if not exschem_ids[id] then
		return exschem_return(id, 0, "Action killed")
	end
	if not iterator then
		iterator = posIterator(pos1, pos2, part)
	end
	local pos = iterator()
	if not pos then
		return exschem_return(id)
	end
	local pos_ = vector.add(pos, part)
	pos_.x = math.min(pos_.x, pos2.x)
	pos_.y = math.min(pos_.y, pos2.y)
	pos_.z = math.min(pos_.z, pos2.z)
	if use_worldedit then
		local data = worldedit.serialize(pos, pos_)
		local file, err = io.open(filepath .."/".. pos.x - pos1.x .."_".. pos.y - pos1.y .."_".. pos.z - pos1.z ..".we", "wb")
		if err ~= nil then
			return exschem_return(id, 2, "Writing to file failed")
		end
		file:write(data)
		file:close()
	else
		local manip = minetest.get_voxel_manip()
		manip:read_from_map(pos, pos_)
		minetest.create_schematic(pos, pos_, nil, filepath .."/".. pos.x - pos1.x .."_".. pos.y - pos1.y .."_".. pos.z - pos1.z, nil)
	end
	return minetest.after(delay, exschem_save, pos1, pos2, use_worldedit, part, filepath, delay, id, iterator)
end

-- Saves the current area defined by pos1 & pos2 asynchronously
-- @param pos1: Vector. Position 1 of area
-- @param pos2: Vector. Position 2 of area
-- @param use_worldedit: Boolean. If true, uses worldedit.serialize(With metadata, slow). If false, uses minetest.create_schematic(Without metadata, fast).
-- @param part: Integer, greater than 0. Defines the length, width & height of one part schematic. part * part * part = volume of one part schematic. Recommended: 10
-- @param filepath: String. Folder name in /my_world/schems/ with all part schematics in it
-- @param delay: Float, greater than/equal 0. Time between saving part schematics. 0 = Every global step, because minetest.after uses minetest.register_globalstep internal. Recommended: 0
-- @param (Optional) callback: Function. Called when an error occured or saving is finished
-- 								 @param id: Integer. Returned by exschem.save
-- 								 @param errcode: Integer
-- 								 @param error: String. Error message
-- @return id: Integer. Needed to use exschem.kill & identify callback
function exschem.save(pos1, pos2, use_worldedit, part, filepath, delay, callback)
	if use_worldedit and (not worldedit or not worldedit.serialize) then
		return nil, 3, "WorldEdit not installed"
	end
	pos1, pos2 = sort_pos(pos1, pos2)
	minetest.mkdir(minetest.get_worldpath() .."/schems")
	filepath = minetest.get_worldpath() .."/schems/".. filepath
	minetest.mkdir(filepath)
	local data = {maxpos = vector.subtract(pos2, pos1), part = part, use_worldedit = use_worldedit and true or nil}
	local file, err = io.open(filepath .."/init.txt", "w")
	if err ~= nil then
		return nil, 2, "Writing to file failed"
	end
	file:write(minetest.serialize(data))
	file:flush()
	file:close()
	local id = #exschem_ids + 1
	exschem_ids[id] = true
	exschem_time[id] = os.time()
	exschem_callback[id] = callback
	minetest.after(0, exschem_save, pos1, pos2, use_worldedit, part, filepath, delay, id)
	return id
end

local function exschem_load(pos1, maxpos, rotation, replacements, use_worldedit, part, filepath, delay, id, iterator, max)
	if not exschem_ids[id] then
		return exschem_return(id, 0, "Action killed")
	end
	if not iterator then
		iterator = posIterator(pos1, vector.add(pos1, maxpos), part)
	end
	local pos = iterator()
	if not pos then
		return exschem_return(id)
	end
	if use_worldedit then
		local file, err = io.open(filepath .."/".. pos.x - pos1.x .."_".. pos.y - pos1.y .."_".. pos.z - pos1.z ..".we", "rb")
		if err ~= nil then
			return exschem_return(id, 1, "Reading from file failed")
		end
		local data = file:read("*a")
		file:close()
		local nodes = worldedit.deserialize(pos, data)--WorldEdit crashes if the WE version is older than 15.June.2019, when WE tries to set a schemtic with 0 nodes: https://github.com/Uberi/Minetest-WorldEdit/pull/177
		if nodes and nodes == 0 and (max or 1) < 3 then
			return exschem_load(pos1, maxpos, rotation, replacements, use_worldedit, part, filepath, delay, id, iterator, (max or 0) + 1)
		end
	else
		local manip = minetest.get_voxel_manip()
		manip:read_from_map(pos, vector.add(pos, part))
		minetest.place_schematic(pos, filepath .."/".. pos.x - pos1.x .."_".. pos.y - pos1.y .."_".. pos.z - pos1.z, rotation, replacements, true)
	end
	return minetest.after(delay, exschem_load, pos1, maxpos, rotation, replacements, use_worldedit, part, filepath, delay, id, iterator)
end


-- Loads/Places the part schematics of filepath at pos1 asynchronously
-- @param pos1: Vector. Position 1 where schematic should be placed
-- @param rotation: Number, multiple of 90. Rotates the schematic. Only works when use_worldedit were false at exschem.save, because WorldEdit doesn't support rotate on place. Recommended: 0
-- @param replacements: Table. Only works when use_worldedit were false at exschem.save, because WorldEdit doesn't support replace on place. Recommended: {}
-- 				rotation & replacements can be seen here: https://github.com/minetest/minetest/blob/0.4.15/doc/lua_api.txt#L2529
-- @param filepath: String. Folder name in /my_world/schems/ with all part schematics in it
-- @param delay: Float, greater than/equal 0. Time between loading part schematics. 0 = Every global step, because minetest.after uses minetest.register_globalstep internal. Recommended: 0
-- @param (Optional) callback: Function. Called when an error occured or saving is finished
-- 								 @param id: Integer. Returned by exschem.save
-- 								 @param errcode: Integer
-- 								 @param error: String. Error message
-- @return id: Integer. Needed to use exschem.kill & identify callback
function exschem.load(pos1, rotation, replacements, filepath, delay, callback)
	filepath = minetest.get_worldpath() .."/schems/".. filepath
	local file, err = io.open(filepath .."/init.txt", "r")
	if err ~= nil then
		return nil, 1, "Reading from file failed"
	end
	local data = minetest.deserialize(file:read("*a"))
	file:close()
	if data.use_worldedit and (not worldedit or not worldedit.deserialize) then
		return nil, 3, "WorldEdit not installed"
	end
	local id = #exschem_ids + 1
	exschem_ids[id] = true
	exschem_time[id] = os.time()
	exschem_callback[id] = callback
	minetest.after(0, exschem_load, pos1, data.maxpos, rotation, replacements, data.use_worldedit and true or false, data.part, filepath, delay, id)
	return id
end

-- Kills the current asynchronous action(saving/loading) by id
-- @param id: Integer. Returned by exschem.save & exschem.load
function exschem.kill(id)
	exschem_ids[id] = false
end

local function convert_time(time, str)
  local minute = 60
  local hour = 60 * minute
  local day = 24 * hour
  local year = 365 * day
	
	local function convert(unit, unitstr)
		time = math.floor((time / unit) + 0.5)
		return string.format("%s %s%s %s", time, unitstr, (time > 1 and "s" or ""), str or "")
	end
	
	if type(time) ~= "number" then
		return string.format("infinite %s", str or "")
  elseif time > year then
		return convert(year, "year")
  elseif time > day then
		return convert(day, "day")
  elseif time > hour then
    return convert(hour, "hour")
  elseif time > minute then
    return convert(minute, "minute")
  else
    return convert(time, "second")
  end
end

local function chatcommand_callback(message, id, time, errcode, err)
	local name
	for key, value in pairs(chatcommand_data) do
		if value.id == id then
			name = key
			break
		end
	end
	if not name then
		return
	end
	if not errcode then
		minetest.chat_send_player(name, "Finished ".. message:lower() .." after ".. convert_time(time))
	else
		minetest.chat_send_player(name, message .." error: ".. err)
	end
	chatcommand_data[name].id = nil
end

local function chatcommand_callback_save(id, time, errcode, err)
	chatcommand_callback("Saving", id, time, errcode, err)
end

local function chatcommand_callback_load(id, time, errcode, err)
	chatcommand_callback("Loading", id, time, errcode, err)
end

minetest.register_chatcommand("exschem", {
	description = "Save and place lag free schematics",
	params = "pos1 [<x> <y> <z>] | pos2 [<x> <y> <z>] | save <file> [<use_worldedit> [<part> [<delay>]]] | load <file> [<rotation> [<delay>]] | kill",
	privs = {server = true},
	func = function(name, param)
		local params = param:split(" ")
		if param == "" or #params == 0 then
			return false, "No params found. See /help exschem"
		end
		local option = params[1]:lower()
		table.remove(params, 1)
		param = table.concat(params, " ")
		if not chatcommand_data[name] then
			chatcommand_data[name] = {}
		end
		if option == "pos1" then
			local found, _, x, y, z = param:find("^(-?%d+)[, ](-?%d+)[, ](-?%d+)$")
			if not found then
				local pos = vector.round(minetest.get_player_by_name(name):getpos())
				chatcommand_data[name].pos1 = pos
			else
				chatcommand_data[name].pos1 = vector.round({x = tonumber(x), y = tonumber(y), z = tonumber(z)})
			end
			return true, "First position set to ".. chatcommand_data[name].pos1.x ..", ".. chatcommand_data[name].pos1.y ..", ".. chatcommand_data[name].pos1.z
		elseif option == "pos2" then
			local found, _, x, y, z = param:find("^(-?%d+)[, ](-?%d+)[, ](-?%d+)$")
			if not found then
				local pos = vector.round(minetest.get_player_by_name(name):getpos())
				chatcommand_data[name].pos2 = pos
			else
				chatcommand_data[name].pos2 = vector.round({x = tonumber(x), y = tonumber(y), z = tonumber(z)})
			end
			return true, "Second position set to ".. chatcommand_data[name].pos2.x ..", ".. chatcommand_data[name].pos2.y ..", ".. chatcommand_data[name].pos2.z
		elseif option == "save" then
			if chatcommand_data[name].id then
				return false, "Action running. Please kill current action before starting new one. See /help exschem"
			elseif not chatcommand_data[name].pos1 or not chatcommand_data[name].pos2 then
				return false, "No positions set. See /help exschem"
			elseif not params[1] or params[1] == "" then
				return false, "No file selected. See /help exschem"
			elseif params[3] and (type(tonumber(params[3])) ~= "number" or tonumber(params[3]) <= 0 or tonumber(params[3]) % 1 ~= 0) then
				return false, "Part must be a number greater than 0 and multiple of 1. Default: 10"
			elseif params[4] and (type(tonumber(params[4])) ~= "number" or tonumber(params[4]) < 0) then
				return false, "Delay must be a number greater than or equal 0. Default: 0"
			end
			local errcode, err
			chatcommand_data[name].id, errcode, err = exschem.save(chatcommand_data[name].pos1, chatcommand_data[name].pos2, params[2] and minetest.is_yes(params[2]) or false, tonumber(params[3]) or 10, params[1], tonumber(params[4]) or 0, chatcommand_callback_save)
			if chatcommand_data[name].id then
				return true, "Started saving"
			else
				return false, "Saving error: ".. err
			end
		elseif option == "load" then
			if chatcommand_data[name].id then
				return false, "Action running. Please kill current action before starting new one. See /help exschem"
			elseif not chatcommand_data[name].pos1 then
				return false, "No position set. See /help exschem"
			elseif not params[1] or params[1] == "" then
				return false, "No file selected. See /help exschem"
			elseif params[2] and not (params[2] == "random" or (type(tonumber(params[2])) == "number" and tonumber(params[2]) % 90 == 0)) then
				return false, "Rotation must be random or a number multiple of 90. Default: 0"
			elseif params[3] and (type(tonumber(params[3])) ~= "number" or tonumber(params[3]) < 0) then
				return false, "Delay must be a number greater than or equal 0. Default: 0"
			end
			local errcode, err
			chatcommand_data[name].id, errcode, err = exschem.load(chatcommand_data[name].pos1, (params[2] and params[2] == "random") and "random" or (tonumber(params[2]) or 0), false, params[1], tonumber(params[3]) or 0, chatcommand_callback_load)
			if chatcommand_data[name].id then
				return true, "Started loading"
			else
				return false, "Loading error: ".. err
			end
		elseif option == "kill" then
			if not chatcommand_data[name].id then
				return false, "No action running"
			end
			exschem.kill(chatcommand_data[name].id)
			chatcommand_data[name].id = nil
			return true, "Action killed"
		end
end})

