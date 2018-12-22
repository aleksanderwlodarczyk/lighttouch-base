function extract_header (modulepath)
  local header = ""
  local line_num = 0
  for line in io.lines(modulepath .. ".lua") do
    line_num = line_num + 1
    header = header .. line .. "\n" -- get only first 3 lines
    if line_num == 3 then break end
  end

  return scl.to_table(header) -- decode scl string into a lua table
end

function write_events (created_file, header)
  created_file:write("local event = { \"" .. header.event[1] .. "\"") -- put values from yaml in lua form
  for _, yaml_event in ipairs(header.event) do
    if yaml_event ~= header.event[1] then
      created_file:write(', "' .. yaml_event .. '"') -- put all events to 'local event = { }'
    end
  end
  created_file:write(" }")
end

function set_priority (created_file, header)
  created_file:write("\nlocal priority = " .. header.priority .. " \n\n")
end

function write_input_parameters (created_file, header)
  if header.input_parameters[1] then
    created_file:write("local input_parameters = { " .. "\"" .. header.input_parameters[1] .. "\"")
    for k, v in pairs(header.input_parameters) do
      if not table.contains(_G.every_events_actions_parameters, v) then table.insert( _G.every_events_actions_parameters, v ) end
      if k ~= 1 then
        created_file:write(", \"" .. v .. "\"")
      end
    end
    created_file:write("}\n")
  end
end

function write_function (created_file, header, modulepath)
  created_file:write("local function action(arguments)\n") -- function wrapper
  for k, v in pairs(header.input_parameters) do
    created_file:write("\n\tlocal " .. v .. " = " .. "arguments[\"" .. v .. "\"]")
  end
  line_num = 0
  for line in io.lines(modulepath .. ".lua") do
    line_num = line_num + 1
    if line_num > 3 then
      created_file:write(line .. "\n\t")
    end
  end
  created_file:write("\nend")
end

function write_return (created_file, header)
  created_file:write("\n\nreturn{\n\tevent = event,\n\taction = action,\n\tpriority = priority,\n\tinput_parameters = input_parameters\n}") -- ending return
end

local default_package_searchers2 = package.searchers[2]
package.searchers[2] = function(name)
  if string.match( name, "actions") then
    package.preload[name] = function(modulename)
      local created_file = io.open("module.lua", "w+")
      local modulepath = string.gsub(modulename, "%.", "/")
      local path = "/"
      local filename = string.gsub(path, "%?", modulepath)
      local file = io.open(filename, "rb")
      if file then
        local header = extract_header(modulepath)

        write_events(created_file, header)
        set_priority(created_file, header)
        write_input_parameters(created_file, header)
        write_function(created_file, header, modulepath)
        write_return(created_file, header)

        created_file:close()
        -- Compile and return the module
        local to_compile = io.open("module.lua", "rb")
        return assert(load(assert(to_compile:read("*a")), modulepath))
      end
    end
    return require(name)
  else
    return default_package_searchers2(name)
  end
end

function create_actions (package_name)
  local package_path = _G.packages_path .. "/" .. package_name .. "/"
  local actions_path = package_path .. "actions/"
  local action_files = {} -- actions path is optional
  if fs.exists(actions_path) then
    action_files = fs.get_all_files_in(actions_path)
  end

  for _, file_name in ipairs(action_files) do
    log.trace("[patching] action " .. ansicolors('%{underline}' .. file_name))

    local action_require_name = "packages." .. package_name .. ".actions." .. string.sub( file_name, 0, string.len( file_name ) - 4 )
    local action_require = require(action_require_name)

    for k, v in pairs(action_require.event) do
      local event = _G.events[v]
      if event then
        table.insert( _G.events_actions[v], action_require )
        local action = event:addAction(
          function(action_arguments)
            log.debug("[running] action " .. ansicolors('%{underline}' .. file_name) .. " with priority " .. action_require.priority )
            -- TODO: figure out what to do if more than one responses are returned
            possibleResponse = action_require.action(action_arguments)
            if possibleResponse ~= nil then
              if possibleResponse.body ~= nil then
                _G.lighttouch_response = possibleResponse
                if events["outgoing_response_about_to_be_sent"] then
                  events["outgoing_response_about_to_be_sent"]:trigger({response = possibleResponse})
                end
              end
            end
            log.debug("[completed] action " .. ansicolors('%{underline}' .. file_name) )
          end
        )
        event:setActionPriority(action, action_require.priority)
        
        --if isDisabled(file_name) then
        --  event:disableAction(action)
        --end
      else
        log.error("event " .. v .. " doesn't exist")
      end
    end
  end

  log.trace("[patched] actions for package " .. ansicolors('%{underline}' .. package_name))
end
--

-- actions requiring
-- runs the function against all packages in packages_path
each(fs.directory_list(_G.packages_path), create_actions)
