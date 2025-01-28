--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local defaults = require("neo-tree.sources.tests.defaults")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local bsp_utils = require("bsp.utils")
local bsp = require("bsp")
local pt = require('bsp.protocol')
local ms = require('bsp.protocol').Methods

vim.api.nvim_create_augroup('neo-tree-tests', {})

---@type bsp.Client
local client = nil

---@type [string, bsp.TestCaseDiscoveredData]
local test_case_discovery_results = {}

---@type [string, bsp.TestFinish]
local test_outcomes = {}

local function register_test_run_result_events(state)
  local handles = {}
  vim.api.nvim_create_autocmd("User",
    {
      group = 'neo-tree-tests',
      pattern = 'BspProgress:start',
      callback = function(ev)
        local data = ev.data
        if client and data.client_id == client.id then
          ---@type bsp.TaskStartParams
          local result = ev.data.result

          if result.dataKind == bsp.protocol.Constants.TaskStartDataKind.TestTask then
            local tokenId = data.client_id .. ":" .. result.originId
            handles = {}
            handles[tokenId] = {}
          end
        end
      end
    })

  vim.api.nvim_create_autocmd("User",
    {
      group = 'neo-tree-tests',
      pattern = 'BspProgress:finish',
      callback = function(ev)
        local data = ev.data
        if client and data.client_id == client.id then
          ---@type bsp.TaskFinishParams
          local result = ev.data.result

          local tokenId = data.client_id .. ":" .. result.originId

          if result.dataKind == bsp.protocol.Constants.TaskFinishDataKind.TestReport then

            ---@type bsp.TestReport
            local test_report = result.data
            local lines = {}
            table.insert(lines, "Target: " .. vim.uri_to_fname(test_report.target.uri))
            table.insert(lines, "")

            for _, value in pairs(handles[tokenId]) do
              table.insert(lines, value)
            end
            table.insert(lines, "")
            table.insert(lines, "Total: " .. test_report.time .. " ms")
            table.insert(lines, "")
            table.insert(lines, "Passed: " .. test_report.passed .. " " ..
                                "Failed: " .. test_report.failed .. " " ..
                                "Ignored: " .. test_report.ignored .. " " ..
                                "Cancelled: " .. test_report.cancelled .. " " ..
                                "Skipped: " .. test_report.skipped)

            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
            local opts = {
              title = "Test Report",
              title_pos = "center",
              relative = "editor",
              width = 80, height = 30,
              col = 60, row = 10,
              anchor = "NW",
              border = "single",
              style = "minimal"
            }
            local win = vim.api.nvim_open_win(buf, true, opts)
            -- optional: change highlight, otherwise Pmenu is used
            vim.api.nvim_set_option_value('winhl', 'Normal:MyHighlight', {win=win})
          elseif result.dataKind == bsp.protocol.Constants.TaskFinishDataKind.TestFinish then

            ---@type bsp.TestFinish
            local test_finish = result.data

            local m = vim.split(test_finish.message, "\n", {plain=true})
            local lines = {}
            for _, v in pairs(m) do
              table.insert(lines, " " .. v)
            end

            local fqn = test_finish.displayName
            local node = state.tree:get_node(fqn)

            if node ~= nil then
              node.extra.test_output = lines
            end
          end
        end
      end
    })
end

local M = {
  name = "tests",
  display_name = "󰙨 Tests"
}

---@class neo-tree-tests.TestNodeExtra
---@field bufnr integer Buffer number 
---@field client_id integer BSP client id from which the test was retrieved
---@field position integer[] (row, col) tuple Test position inside the test file
---@field build_target bsp.BuildTargetIdentifier BuildTarget where the test is defined
---@field path string Path to the test file
---@field test_output string[]|nil Test output

---@class NuiNode.TestNode
---@field id string Full qualified name of test case
---@field name string User friendly name of test case
---@field stat_provider string Provider name for stat

---Returns the stats for the given node in the same format as `vim.loop.fs_stat`
---@param node neo-tree-tests.Node NuiNode to get the stats for.
--
---@class StatTime
--- @field sec number
---
---@class neo-tree-tests.TestStat
---@field full_qualified_name string
---@field test_run_state bsp.StatusCode
---@field mtime StatTime
---
--- @return neo-tree-tests.TestStat Stats for the given node.
M.get_node_stat = function(node)
  return {
    full_qualified_name = node.id,
    position = node.position,
    test_run_state = "unknown",
    mtime = { sec = 1692617750 },
  }
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path)
  -- if path == nil then
  --   path = vim.fn.getcwd()
  -- end
  -- state.path = path
  --
  local clients = bsp.get_clients()

  if next(clients) then
    client = clients[1]
  end

  assert(client, "no connected bsp client could be found")

  local items = M.__get_test_files(state)

  renderer.show_nodes(items, state)
end


function M.__get_test_files(state)

  local default_request_timeout = 10000

  ---@type { err: bp.ResponseError|nil, result: bsp.WorkspaceBuildTargetsResult }|nil
  local result = client.request_sync(ms.workspace_buildTargets, nil, default_request_timeout, 0)
  if not result or result.err then
    return {}
  end

  local targets = vim.iter(result.result.targets)
    ---@param t bsp.BuildTarget
    :filter(function (t)
      return t.capabilities.canTest
    end)
    ---@param t bsp.BuildTarget
    :map(function (t)
      return t.id
    end)
    :totable()

  local origin_id = bsp_utils.new_origin_id()

  ---@type bsp.TestCaseDiscoveredParams
  local testCaseDiscoveryParams = {
    originId = origin_id,
    targets = targets,
  }

  test_case_discovery_results = {}

  local wait_result = M._wait_for_test_task_results(origin_id)
  ---@type { err: bp.ResponseError|nil, result: bsp.TestCaseDiscoveredResult }|nil
  local discovery_result = client.request_sync(ms.buildTarget_testCaseDiscovery, testCaseDiscoveryParams, default_request_timeout, 0)

  if not discovery_result or discovery_result.err then
    return {}
  end

  if not wait_result() then
    return {}
  end

  local tests_list = {}
  for _, test_case in pairs(test_case_discovery_results) do
    ---@class neo-tree-tests.Node: NuiNode.TestNode
    ---@field id string FullyQualifiedName of the test case
    ---@field name string Display name of the test
    ---@field stat_provider string Stat provider from which the nodes where retrieved
    ---@field type string Type of the node
    ---@field path string Full path of the test file
    ---@field stat neo-tree-tests.TestStat
    ---@field extra neo-tree-tests.TestNodeExtra
    local node = {
      id = test_case.fullyQualifiedName,
      name = test_case.displayName,
      stat_provider = "bsp-tests-provider",
      type = "test_case",
      path = test_case.filePath,
      extra = {
        bufnr = -1,
        position = { tonumber(test_case.line) - 2, 0 },
        build_target = test_case.buildTarget,
        path = test_case.filePath,
        client_id = client.id,
        test_output = nil
      }
    }
    table.insert(tests_list, node)
  end

  register_test_run_result_events(state)

  return tests_list
end

function M._wait_for_test_task_results(origin_id)

  local finished = false

  vim.api.nvim_create_autocmd("User",
    {
      group = 'neo-tree-tests',
      pattern = 'BspProgress:progress',
      callback = function(ev)
        ---@type bsp.TaskProgressParams
        local result = ev.data.result
        if result.originId == origin_id then
          if result.dataKind == pt.TaskProgressDataKind.TestCaseDiscovered then
            ---@type bsp.TestCaseDiscoveredData
            local data = result.data
            local key = data.buildTarget.uri .. ":" .. data.fullyQualifiedName
            test_case_discovery_results[key] = data
          end
        end
      end
    })

  vim.api.nvim_create_autocmd("User",
    {
      group = 'neo-tree-tests',
      pattern = 'BspProgress:finish',
      callback = function(ev)
        ---@type bsp.TaskFinishParams
        local result = ev.data.result
        if result.originId == origin_id then
          if result.dataKind == pt.TaskFinishDataKind.TestCaseDiscoveryFinish then
            finished = true
          elseif result.dataKind == pt.TaskFinishDataKind.TestFinish then
            test_outcomes[origin_id] = result.data
          elseif result.dataKind == pt.TaskFinishDataKind.TestReport then
            finished = true
          end
        end
      end
    })

  return function ()
    local wait_result = vim.wait(10000,
      function ()
        return finished
      end,
      10)

    return wait_result
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)

  -- redister or custom stat provider to override the default libuv one
  require("neo-tree.utils").register_stat_provider("bsp-tests-provider", M.get_node_stat)


  -- You most likely want to use this function to subscribe to events
  -- if config.use_libuv_file_watcher then
  --   manager.subscribe(M.name, {
  --     event = events,
  --     handler = function(args)
  --       manager.refresh(M.name)
  --     end,
  --   })
  -- end
end

M.default_config = defaults

return M
