--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local defaults = require("neo-tree.sources.tests.defaults")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")

local path = require("plenary.path")

local bsp_utils = require("bsp.utils")
local bsp = require("bsp")
local pt = require('bsp.protocol')
local ms = require('bsp.protocol').Methods

local M = {
  name = "tests",
  display_name = "󰙨 Tests"
}

---@type table<integer, neo-tree-tests.Node[]>
local tests_tree = {}

vim.api.nvim_create_augroup('neo-tree-tests', {})

---Convert BSP test case to NuiNode
---@param test_case bsp.TestCaseDiscoveredData
---@param client_id integer BSP client ID
---@return neo-tree-tests.Node
local function convert_test_case_to_node(test_case, client_id)
  ---@class neo-tree-tests.Node: NuiNode.TestNode
  ---@field id string TestCase ID
  ---@field name string Display name of the test
  ---@field stat_provider string Stat provider from which the nodes where retrieved
  ---@field type string Type of the node
  ---@field path string Full path of the test file
  ---@field extra neo-tree-tests.TestNodeExtra
  local node = {
    id = test_case.id,
    name = test_case.displayName,
    type = "test_case",
    path = test_case.filePath,
    extra = {
      bufnr = -1,
      fully_qualified_name = test_case.fullyQualifiedName,
      position = { tonumber(test_case.line) - 2, 0 },
      build_target = test_case.buildTarget,
      path = test_case.filePath,
      client_id = client_id,
      test_output = nil,
      test_run_state = "unknown",
    }
  }
  return node
end

---Adds node to the tests tree
---@param client_id integer ID of the BSP client
---@param node neo-tree-tests.Node
---@param workspace_dir string
local function add_node_to_state(client_id, node, workspace_dir)

  if not tests_tree[client_id] then
    tests_tree[client_id] = {}
  end

  local parent_node_id = node.extra.build_target.uri

  local parent = vim.iter(tests_tree[client_id]):find(function (v) return v.id == parent_node_id end)

  if not parent then
    local name = path:new(vim.uri_to_fname(parent_node_id)):make_relative(workspace_dir)
    parent = {
      id = parent_node_id,
      name = name,
      type = "build_target",
      extra = {
        test_run_state = "unknown"
      }
    }
    table.insert(tests_tree[client_id], parent)
  end

  if not parent.children then
    parent.children = {}
    table.insert(parent.children, node)
  else
    local old_item_index = nil
    for index, value in ipairs(parent.children) do
      if not old_item_index and value.id == node.id then
        old_item_index = index
      end
    end

    if old_item_index then
      -- print("item found in parent replace: index=" .. vim.inspect(old_item_index) .. " id==" .. node.id)
      table.remove(parent.children, old_item_index)
      table.insert(parent.children, old_item_index, node)
      -- print("after children: " .. vim.inspect(parent.children))
    else
      -- print("no item found in parent: id==" .. vim.inspect(node.id))
      table.insert(parent.children, node)
    end
  end
end

---@param source_name string
local function register_test_run_result_events(source_name)
  vim.api.nvim_create_autocmd("User",
    {
      group = 'neo-tree-tests',
      pattern = 'BspProgress:start',
      callback = function(ev)
        local data = ev.data
        ---@type bsp.TaskStartParams
        local result = ev.data.result
        if result.dataKind == bsp.protocol.Constants.TaskStartDataKind.TestTask then
          local tokenId = data.client_id .. ":" .. result.originId
          -- TODO: think if we have something to do here
        elseif result.dataKind == bsp.protocol.Constants.TaskStartDataKind.TestCaseDiscoveryTask then
          tests_tree[data.client_id] = {}
        end
      end
    })

  vim.api.nvim_create_autocmd("User",
    {
      group = 'neo-tree-tests',
      pattern = 'BspProgress:progress',
      callback = function(ev)
        ---@type bsp.TaskProgressParams
        local result = ev.data.result
        if result.dataKind == pt.TaskProgressDataKind.TestCaseDiscovered then
          local state = manager.get_state(source_name)
          ---@type bsp.TestCaseDiscoveredData
          local test_case = result.data
          local client_id = ev.data.client_id
          local node = convert_test_case_to_node(test_case, client_id)
          local client = bsp.get_client_by_id(client_id)
          assert(client, "client could not be found for id: " .. client_id)
          add_node_to_state(client_id, node, client.workspace_dir)
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
        if result.dataKind == pt.TaskFinishDataKind.TestCaseDiscoveryFinish then
          -- TODO: think if we need to do here something
        elseif result.dataKind == bsp.protocol.Constants.TaskFinishDataKind.TestReport then
          ---@type bsp.TestReport
          local test_report = result.data
          local lines = {}
          table.insert(lines, "Target: " .. vim.uri_to_fname(test_report.target.uri))

          table.insert(lines, "")
          table.insert(lines, "Passed: " .. test_report.passed .. " " ..
                              "Failed: " .. test_report.failed .. " " ..
                              "Ignored: " .. test_report.ignored .. " " ..
                              "Cancelled: " .. test_report.cancelled .. " " ..
                              "Skipped: " .. test_report.skipped)
          table.insert(lines, "")
          table.insert(lines, "Total: " .. test_report.time .. " ms")

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
          -- local win = vim.api.nvim_open_win(buf, true, opts)
          -- -- optional: change highlight, otherwise Pmenu is used
          -- vim.api.nvim_set_option_value('winhl', 'Normal:MyHighlight', {win=win})
        elseif result.dataKind == bsp.protocol.Constants.TaskFinishDataKind.TestFinish then

          ---@type bsp.TestFinish
          local test_finish = result.data

          local m = vim.split(test_finish.message, "\n", {plain=true})
          local lines = {}
          for _, v in pairs(m) do
            table.insert(lines, " " .. v)
          end

          --TODO: displayName is not FQN it does not include test case parameters
          local test_case_id = test_finish.id
          local state = manager.get_state(source_name)

          local node = nil
          if state.tree then
            node = state.tree:get_node(test_case_id)
          end

          if node ~= nil then
            node.extra.test_run_state = test_finish.status
            node.extra.test_output = lines
            renderer.redraw(state)
          end
        end
      end
    })
end

---@class neo-tree-tests.TestNodeExtra
---@field bufnr integer Buffer number 
---@field fully_qualified_name string FullyQualifiedName of the test case
---@field client_id integer BSP client id from which the test was retrieved
---@field position integer[] (row, col) tuple Test position inside the test file
---@field build_target bsp.BuildTargetIdentifier BuildTarget where the test is defined
---@field path string Path to the test file
---@field test_output string[]|nil Test output

---@class NuiNode.TestNode
---@field id string Full qualified name of test case
---@field name string User friendly name of test case
---@field stat_provider string Provider name for stat

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.navigate = function(state, path, path_to_reveal, callback)
  -- if path == nil then
  --   path = vim.fn.getcwd()
  -- end
  -- state.path = path
  --

  local root_nodes = {}
  for client_id, test_tree in pairs(tests_tree) do
    local client = bsp.get_client_by_id(client_id)
    assert(client, "could not retrieve bsp client")
    local root = {
      id = "bsp:client_id:" .. client_id,
      name = "[BSP]: " .. client.name,
      type = "bsp_client",
      children = test_tree or {}
    }
    table.insert(root_nodes, root)
  end

  renderer.show_nodes(root_nodes, state)

  -- if state and state.tree then
  --   renderer.show_nodes(tests_tree or {}, state, "test_root")
  -- else
  --   local root = {
  --     id = "test_root",
  --     name = "tests",
  --     type = "unknown",
  --     -- loaded = true,
  --     children = tests_tree or {}
  --   }
  --   renderer.show_nodes({root}, state)
  -- end
end

---@param source_name any
---@param force boolean Force a refresh
---@param callback function
M.request_test_cases = function(source_name, force, callback)
  local state = manager.get_state(source_name)
  if state.loading then
    return
  end
  state.loading = true

  local default_request_timeout = 10000
  local clients = bsp.get_clients()
  for _, client in pairs(clients) do
    if not next(client.test_cases) or force then

      local build_targets = nil
      if next(client.build_targets) then
        build_targets = vim.tbl_values(client.build_targets)
      else
        ---@type { err: bp.ResponseError|nil, result: bsp.WorkspaceBuildTargetsResult }|nil
        local result = client.request_sync(ms.workspace_buildTargets, nil, default_request_timeout, 0)
        if result and not result.err then
          build_targets = result.result.targets
        end
      end

      assert(build_targets, "could not retrieve build targets")

      local test_targets = vim.iter(build_targets)
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
        targets = test_targets,
      }

      client.request(ms.buildTarget_testCaseDiscovery, testCaseDiscoveryParams, function ()
        if type(callback) == "function" then
          callback()
        end
      end, 0)
    else
      local test_cases = vim.iter(vim.tbl_values(client.test_cases))
        :flatten()
        :totable()
      for _, test_case in pairs(test_cases) do
        local node = convert_test_case_to_node(test_case, client.id)
        add_node_to_state(client.id, node, client.workspace_dir)
      end

      if type(callback) == "function" then
        callback()
      end
    end
  end

  state.loading = false
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  register_test_run_result_events(M.name)
  M.request_test_cases(M.name, false, nil)

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
