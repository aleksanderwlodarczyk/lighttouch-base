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

function write_priority (created_file, header, priority)
  if priority > 100 then priority = 100 end

  created_file:write("local priority = " .. priority)
end

function write_events_table (created_file, header)
  created_file:write("\nlocal events_table = { " .. "\"" .. header.events_table[1] .. "\"")
  for k, v in pairs(header.events_table) do
    if k ~= 1 then
      created_file:write(", " .. "\"" .. v .. "\"")
    end
  end
  created_file:write("}")
end

function write_input_parameter (created_file, header)
  created_file:write("\nlocal input_parameter = \"" .. header.input_parameter .. "\"")
end

function write_rule_function (created_file, header, modulename, priority, modulepath)
  created_file:write("\nlocal events_parameters = { }")
  created_file:write("\nlocal function rule(" .. header.input_parameter)
    for k, v in pairs (_G.every_events_actions_parameters) do
      if v ~= header.input_parameter then
        created_file:write(", " .. v)
      end
    end
    created_file:write(")")

    created_file:write("\n\tlog.debug('[evaluating] " .. _G.ansicolors('%{underline}' .. modulename) .. " with priority " .. priority .. " starting to evaluate')")

    created_file:write("\n\tlocal arguments_strings_dictionary = { }")
    created_file:write("\n\targuments_strings_dictionary[\"" .. header.input_parameter .. "\"] = " .. header.input_parameter)
    for k, v in pairs (_G.every_events_actions_parameters) do -- matching rule arguments with action required parameters, so events_parameters["p1"] = p1
      if v ~= header.input_parameter then
        created_file:write("\n\targuments_strings_dictionary[\"" .. v .. "\"] = " .. v)
      end
    end

    created_file:write("\n\tfor k, v in pairs(events_parameters) do")
      created_file:write("\n\t\tevents_parameters[k] = arguments_strings_dictionary[k]")
    created_file:write("\n\tend")
    created_file:write("\n\tif")
    line_num = 0
    for line in io.lines(modulepath .. ".lua") do
      line_num = line_num + 1
      if line_num > 3 then
        created_file:write("\n\t" .. line)
      end
    end
    created_file:write("\n\tthen")
      created_file:write("\n\t\tlog.trace(\"Rule " .. _G.ansicolors('%{underline}' .. modulename) .. " evaluated as TRUE \")")

      created_file:write("\n\t\tfor k, v in pairs(events_table) do")
        created_file:write("\n\t\t\tevents[v]:trigger(events_parameters)")
      created_file:write("\n\t\tend")
    created_file:write("\n\telse")
      created_file:write("\n\t\tlog.trace(\"Rule " .. _G.ansicolors('%{underline}' .. modulename) .. " evaluated as FALSE \")")
    created_file:write("\n\tend")
  created_file:write("\nend\n") -- bottom rule function wrapper
end

function write_get_events_parameters (created_file, header)
  created_file:write("\nlocal function get_events_parameters(events_actions)")
    created_file:write("\n\tfor k, v in pairs(events_table) do")
      created_file:write("\n\t\tfor k1, v1 in pairs(events_actions[v]) do")
        created_file:write("\n\t\t\tfor k2, v2 in pairs(v1.input_parameters) do")
          created_file:write("\n\t\t\t\tif not events_parameters[v2] then")
            created_file:write("\n\t\t\t\t\tevents_parameters[v2] = \" \"")
          created_file:write("\n\t\t\t\tend")
        created_file:write("\n\t\t\tend")
      created_file:write("\n\t\tend")
    created_file:write("\n\tend")
  created_file:write("\nend")
end

function write_return (created_file, header)
  created_file:write("\nreturn{\n\trule = rule,\n\tpriority = priority,\n\tget_events_parameters = get_events_parameters\n}")
  -- Compile and return the module
end

local default_package_searchers2 = package.searchers[2]
package.searchers[2] = function(name)
  if string.match( name, "rules") then
    package.preload[name] = function(modulename)
      local created_file = io.open("module.lua", "w+")
      local modulepath = string.gsub(modulename, "%.", "/")
      local path = "/"
      local filename = string.gsub(path, "%?", modulepath)
      local file = io.open(filename, "rb")
      if file then
        local header = extract_header(modulepath)
        local priority = header.priority or 1

        write_priority(created_file, header, priority)
        write_events_table(created_file, header)
        write_input_parameter(created_file, header)
        write_rule_function(created_file, header, modulename, priority, modulepath)
        write_get_events_parameters(created_file, header)
        write_return(created_file, header)

        created_file:close()
        local to_compile = io.open("module.lua", "rb")
        return assert(load(assert(to_compile:read("*a")), modulepath))
      end
    end
    return require(name)
  else
    return default_package_searchers2(name)
  end
end

function create_rules (package_name)
  local rules_path = _G.packages_path .. "/".. package_name .. "/rules/"
  local rule_files = {} -- get all rules from this package
  -- Rules path is optional
  if fs.exists(rules_path) then
    rule_files = fs.get_all_files_in(rules_path)
  end

  for _, file_name in ipairs(rule_files) do
    if file_name ~= "lua_files/" then

      local rule_require_name = "packages." .. package_name .. ".rules." .. string.sub(file_name, 0, string.len( file_name ) - 4)
      local rule_require = require(rule_require_name)
      rule_require.get_events_parameters(_G.events_actions) -- let the rule know which parameters it needs to its events actions
      log.debug("[loading] rule " .. ansicolors('%{underline}' .. rule_require_name))

      --table.insert(_G.rules, rule_require)
      _G.rules_priorities[rule_require_name] = rule_require.priority
    end
  end
end


-- Runs the function against all packages in packages_path
each(fs.directory_list(_G.packages_path), create_rules)
