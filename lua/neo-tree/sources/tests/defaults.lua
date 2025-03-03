local config = {
  renderers = {
    directory = {
      { "icon" },
      { "name" },
    },
    bsp_client = {
      { "name" },
    },
    build_target = {
      { "icon",
        icons = {
          test_passed = "",
          test_failed = "",
          test_warn = "󰀨",
          test_skipped = "",
          test_unknown = "",
        },
      },
      { "name" },
    },
    test_case = {
      { "icon",
        icons = {
          test_passed = "",
          test_failed = "",
          test_warn = "󰀨",
          test_skipped = "",
          test_unknown = "",
        },
      },
      { "name" },
    },
  },
  window = {
    mappings = {
      ["r"] = "run",
      ["o"] = "output",
      ["i"] = "jumpto",
      ["u"] = "stop",
      ["d"] = "debug",
      ["D"] = "show_debug_info",
      ["e"] = "expand_all",
      ["<TAB>"] = "toggle_node"
    },
  },
}

return config
