local config = {
  renderers = {
    directory = {
      { "icon" },
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
      ["<TAB>"] = "expand"
    },
  },
}

return config
