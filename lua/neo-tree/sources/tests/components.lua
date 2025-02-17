-- This file contains the built-in components. Each componment is a function
-- that takes the following arguments:
--      config: A table containing the configuration provided by the user
--              when declaring this component in their renderer config.
--      node:   A NuiNode object for the currently focused node.
--      state:  The current state of the source providing the items.
--
-- The function should return either a table, or a list of tables, each of which
-- contains the following keys:
--    text:      The text to display for this item.
--    highlight: The highlight group to apply to this text.

local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")
local c = require("bsp.protocol").Constants
local utils = require("neo-tree.utils")

local M = {}

M.icon = function(config, node, state)
  if node.type ~= "test_case" and node.type ~= "build_target" then
    return common.icon(config, node, state)
  end

  local icon = nil
  local padding = config.padding or " "
  local highlight = config.highlight or highlights.FILE_ICON
  if node.type == "test_case" or node.type == "build_target" then
    local nd_extra = node.extra

    if nd_extra.test_run_state == c.TestStatus.Passed then
      icon = config.icons.test_passed
      highlight = "DiagnosticSignOk"
    elseif nd_extra.test_run_state == c.TestStatus.Failed or
           nd_extra.test_run_state == c.TestStatus.Cancelled then
      icon = config.icons.test_failed
      highlight = "DiagnosticSignError"
    elseif nd_extra.test_run_state == c.TestStatus.Skipped then
      icon = config.icons.test_skipped
      highlight = "DiagnosticSignHint"
    elseif nd_extra.test_run_state == c.TestStatus.Ignored then
      icon = config.icons.test_warn
      highlight = "DiagnosticSignWarn"
    elseif nd_extra.test_run_state == "unknown" then
      icon = config.icons.test_unknown
      highlight = "DiagnosticSignWarn"
    else
      print("draw icon for: " .. vim.inspect(nd_extra))
    end
  end
  return {
    text = icon .. padding,
    highlight = highlight,
  }
end

M.name = function(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_NAME
  end
  if node:get_depth() == 1 then
    highlight = highlights.ROOT_NAME
  end
  return {
    text = node.name,
    highlight = highlight,
  }
end

return vim.tbl_deep_extend("force", common, M)
