--#! /usr/bin/env lua

-- Original script from https://github.com/daxliar/submerger
--9.08.2019 - set_basetime support added by Oli

-- Default colors to use when writing the merged values
-- they have to be valid html color codes as used inside the <font> tag
local default_color_a = "white"
local default_color_b = "yellow"

-- Utility to covert from a srt timestamp in the format "00:00:00,000" to a number
function str_timestamp_to_seconds( timestamp )
  hours, minutes, seconds, milliseconds = string.match( timestamp, "(%d+):(%d+):(%d+),(%d+)")
  hours = tonumber(hours) * 3600
  minutes = tonumber(minutes) * 60
  seconds = tonumber(seconds)
  milliseconds = tonumber(milliseconds) * 0.001
  return hours + minutes + seconds + milliseconds
end

-- Utility to covert from a number in seconds to an srt timestamp in the format "00:00:00,000"
function seconds_to_str_timestamp( seconds )
  local total_seconds, fractinal_part = math.modf( tonumber(seconds) )
  local total_hours = math.floor(total_seconds / 3600)
  local total_minutes = math.floor(total_seconds / 60) % 60
  total_seconds = total_seconds % 60
  return string.format("%02.f:%02.f:%02.f,%03.f", total_hours, total_minutes, total_seconds, fractinal_part * 1000 )
end

-- Tiny utility function to trim a string
function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Generate an subtitle entry with times and text. Trnslated inserted to be used later on
-- It takes timestamps in both formats
function generate_entry( in_start_time, in_end_time, in_text )
  local insert_start_time = 0
  local insert_end_time = 0
  if type(in_start_time) == "number" then
    insert_start_time = in_start_time
  else
    insert_start_time = str_timestamp_to_seconds(in_start_time)
  end
  if type(in_end_time) == "number" then
    insert_end_time = in_end_time
  else
    insert_end_time = str_timestamp_to_seconds(in_end_time)
  end
  return { start_time=insert_start_time, end_time=insert_end_time, text=in_text, translated={} }
end

-- Main loop to open an SRT file and return a table with all the elements from the file
-- generate_entry is used for every block created
function import_srt( filename )
  local srts = {}
  local file,error = io.open(filename, "r")
  if not err then
    local line_type = "index"
    local last_index = -1
    local current_text = ""
    local current_index = 0
    local current_start_time = nil
    local current_end_time = nil
    while true do
      local line = file:read()
      if line == nil then
        break
      end
      -- first read the index
      if line_type == "index" then
          last_index = current_index
          trimmed_line = trim(line)
          current_index = tonumber(trimmed_line)
          line_type = "time"
          current_text = ""
      -- then get the time interval
      elseif line_type == "time" then
        current_start_time, current_end_time = string.match( line, "(%d+:%d+:%d+,%d+) --.* (%d+:%d+:%d+,%d+)")
        line_type = "text"
      -- and finally get all the lines of text
      elseif line_type == "text" then
        -- until we get an empty line, in this case we restart
        local trimmed_text = trim(string.gsub(line, "\n", ""))
        if trimmed_text == "" then
          line_type = "index"
          table.insert(srts, generate_entry(current_start_time, current_end_time, current_text ) )
        else
          if current_text == "" then
	    	aegisub.debug.out("\n=="..tostring(current_index)..":"..tostring(trimmed_text))
            current_text = trimmed_text
          else
	    	aegisub.debug.out("\n=="..tostring(current_index).."+"..tostring(trimmed_text))
            current_text = current_text .. " " .. trimmed_text
          end
        end
      end
    end
    file:close()
    print("Imported " .. tostring(#srts) .. " blocks from \"" .. tostring(filename) .. "\"")
  else
    print("Error: Can't import file \"" .. tostring(filename) .. "\" for writing!")
  end
  return srts
end

-- Check whether two time intervals overlaps
-- Epsilon used to make every range a bit more 'fat' to help overlapping
function do_intervals_overlap( start_time_a, end_time_a, start_time_b, end_time_b, epsilon )
  return  ((start_time_b - epsilon < end_time_a + epsilon ) and (end_time_b + epsilon > start_time_a - epsilon)) or
          ((start_time_a - epsilon < end_time_b + epsilon ) and (end_time_a + epsilon > start_time_b - epsilon))
end

-- Extract the concatenated string of all the texts from srt using indexes
function extract_text_from_indexes( srt, indexes )
    local final_text = ""
    if srt ~= nil then
      for k,v in pairs(indexes) do
        if final_text == "" then
          final_text = srt[v]["text"]
        else
          final_text = final_text .. " " .. srt[v]["text"]
        end
      end
    end
    return final_text
end

-- Given indexes return the minimum start time and maximum end time from the blocks in srt
function extract_start_end_time_from_indexes( srt, indexes )
  local start_time = 0.0
  local end_time = 0.0
  if srt ~= nil then
    for k,v in pairs(indexes) do
      local current_start_time = srt[v]["start_time"]
      local current_end_time = srt[v]["end_time"]
      if start_time == 0.0 or current_start_time < start_time then
        start_time = current_start_time
      end
      if end_time == 0.0 or current_end_time > end_time then
        end_time = current_end_time
      end
    end
  end
  return start_time, end_time
end

-- Merge two strings and create a valid html string with the two coloured text one after each other
function merge_srt_texts( text_a, text_b, color_a, color_b )
  local selected_color_a = tostring(color_a or default_color_a)
  local selected_color_b = tostring(color_b or default_color_b)
  return string.format("<font color=\"%s\">%s</font><br><font color=\"%s\">%s</font>", selected_color_a, text_a, selected_color_b, text_b )
end

-- Given two tables with the blocks read from the two srt file return a unique table with the new merged srt blocks
-- The returned element has the same structure as the two inputs
function merge_srts( srt_a, srt_b )
  
  local srts = {}
  local error = 0.0  
  local last_previous_overlap = 0
  local inserted_index = 0
  local overlaps = { }

  -- First create a table with all the overlaps
  -- Each overlaps has entries with indexes from A 'srt_a_indexes' and B 'srt_b_indexes'
  for ka,va in pairs(srt_a) do
    
    local current_index = tonumber(ka)
    local current_overlaps = {}
    local removed_previous = false

    for kb,vb in pairs(srt_b) do
      if do_intervals_overlap( va["start_time"], va["end_time"], vb["start_time"], vb["end_time"], error ) then        
        local curret_overlap_index = tonumber( kb )
        table.insert(current_overlaps, curret_overlap_index)
        last_previous_overlap = curret_overlap_index

        if removed_previous == false and #current_overlaps == 2 then
          table.remove(current_overlaps, 1 )
          removed_previous = true
        end
      end
    end

    local insert_in_open_block = false
    if inserted_index > 0 then
      for k,v in pairs(overlaps[inserted_index]["srt_b_indexes"]) do
        if v == last_previous_overlap then
          insert_in_open_block = true
          break
        end
      end
    end

    if insert_in_open_block then
      table.insert( overlaps[inserted_index]["srt_a_indexes"], current_index )
    else
      table.insert( overlaps, { srt_a_indexes={ current_index }, srt_b_indexes=current_overlaps } )
      inserted_index = inserted_index + 1
    end

  end

  -- generate final block from overlaps
  for k,v in pairs(overlaps) do
    local srt_a_indexes = v["srt_a_indexes"]
    local srt_b_indexes = v["srt_b_indexes"]

    local start_time, end_time = extract_start_end_time_from_indexes( srt_a, srt_a_indexes )

    local text_a = extract_text_from_indexes( srt_a, srt_a_indexes )
    local text_b = extract_text_from_indexes( srt_b, srt_b_indexes )

    table.insert(srts, generate_entry(start_time, end_time, merge_srt_texts( text_a, text_b ) ) )
  end
  return srts
end

function setContains(set, key)
    return set[key] ~= nil
end

function hasprop(line,prop) 
	return (setContains(line,prop))
end

-- This function should be called before seconds_to_str_timestamp/ str_timestamp_to_seconds
function set_basetime(srt) 
	local basetime=1 -- Normaly basetime for srt is the second
	if(#srt) then
	   line=srt[1]
	   if(hasprop(line,"layer")) then --but for the line object of a selected line in aegisub
		basetime=1000    --times are in ms so we have to adjust basetime
	   end
	end
       return basetime
end

-- Writes srt data to a file
function write_srt( filename, srt )
  if srt ~= nil then
    local file = io.open(filename, "w")
    if file ~= nil then
      local basetime=set_basetime(srt) 
      for k,v in pairs(srt) do
        file:write(string.format( "%s\n", tostring(k)))
        local start_time = seconds_to_str_timestamp(v["start_time"]/basetime)
        local end_time = seconds_to_str_timestamp(v["end_time"]/basetime)
        file:write(string.format( "%s --> %s\n", start_time, end_time))
        file:write(string.format( "%s\n\n", v["text"] ))
      end
      file:close()
      print("Written " .. tostring(#srt) .. " blocks to \"" .. tostring(filename) .. "\"")
    else
      print("Error: Can't open file \"" .. tostring(filename) .. "\" for writing!")
    end
  else
    print("Error: Nothing to write in the output srt file!")
  end
end

-- Check if running as library or as a program
--if pcall(debug.getlocal, 4, 1) then
--  print("You are using " .. arg[0] .. " as a library")
--else
--  local num_args = #arg
--  if num_args >= 3 or num_args <= 5 then
--
--    default_color_a = arg[4] or default_color_a
--    default_color_b = arg[5] or default_color_b
--
--    write_srt( arg[3], merge_srts( import_srt(arg[1]), import_srt(arg[2]) ) )
--  else
--    print( "Usage: " .. arg[0] .. " <input srt file 1> <input srt file 2> <output srt file> [html color code 1] [html color code 2]")
--  end
--end
