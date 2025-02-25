--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local tests = require("neo-tree.sources.tests")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local popups = require("neo-tree.ui.popups")
local nt_utils = require("neo-tree.utils")

local bsp = require("bsp")
local ms = require("bsp.protocol").Methods
local bsp_utils = require("bsp.utils")

local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

local vim = vim

local M = {}

---@param state any
---@return neo-tree-tests.TestNodeExtra
local function get_node_extra(state)
  local tree = state.tree
  local node = tree:get_node()
  return node.extra
end

M.show_debug_info = function(state)
  local tree = state.tree
  local node = tree:get_node()
  local id = node:get_id()
  local name = node.name

  print(string.format("node: id=%s, name=%s", id, name))
  print("node extra: " .. vim.inspect(node.extra))
end

M.refresh = function(state)
  tests.request_test_cases(tests.name, true);
  manager.refresh(tests.name, state)
end

M.run = function(state)
  local tree = state.tree
  ---@class neo-tree-tests.Node
  local node = tree:get_node()

  if node.type == "test_case" then
    local testParams = {
      originId = bsp_utils.new_origin_id(),
      targets = { node.extra.build_target },
      dataKind = "dotnet-test",
      data = {
        filter = "id==" .. node.id
      }
    }
    ---@class bsp.Client
    local client = bsp.get_client_by_id(node.extra.client_id)

    assert(client, "client with id '" .. node.extra.client_id .. "' could not be retrieved")

    client.request(
      ms.buildTarget_test,
      testParams,
      ---@param err bp.ResponseError|nil
      ---@param result bsp.TestResult
      ---@param context bsp.HandlerContext
      ---@param config table|nil
      function (err, result, context, config)
      end,
    0)
  end
end

M.output = function(state)
  local extra = get_node_extra(state)
  if extra.test_output then
    local popup = Popup({
      enter = true,
      focusable = true,
      relative = "editor",
      border = {
        style = "solid",
        text = {
          top = "[ Test output ]",
          top_align = "center"
        }
      },
      position = "50%",
      size = {
        width = "80%",
        height = "60%",
      },
      buf_options = {
        modifiable = false,
        readonly = true,
      },
    })

    -- set content
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, extra.test_output)

    -- mount/open the component
    popup:mount()

    -- unmount component when cursor leaves buffer
    popup:on(event.BufLeave, function()
      popup:unmount()
    end)
  end
end

M.jumpto = function(state)
  local test_extra = get_node_extra(state)

  local buffers = vim.api.nvim_list_bufs()

  local buf = -1
  for _, bufnr in pairs(buffers) do
    local file_name = vim.api.nvim_buf_get_name(bufnr)
    if file_name == test_extra.path then
      buf = bufnr
      break
    end
  end

  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, test_extra.path)
    vim.api.nvim_buf_call(buf, vim.cmd.edit)
  end

  test_extra.bufnr = buf

  cc.open_with_window_picker(state, function () end)
end

M.stop = function(state)
end
M.debug = function(state)
end
-- M.expand = function(state)
-- end
M.expand_all = function(state)
  local tree = state.tree
  local nodes = tree:get_nodes()

  for _, node in pairs(nodes) do
    if nt_utils.is_expandable(node) and
       node:has_children() then
        local updated = false
        if not node:is_expanded() then
          updated = node:expand()
        end
        if updated then
          renderer.redraw(state)
        end
    end
  end
end

M.open = M.output

cc._add_common_commands(M)

return M
