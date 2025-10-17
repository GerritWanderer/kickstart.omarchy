return {
  "mrjones2014/smart-splits.nvim",
  build = "./kitty/install-kittens.bash",
  lazy = false,
  keys = {
    -- Override LazyVim's default window navigation
    { "<C-h>", function() require("smart-splits").move_cursor_left() end, desc = "Move focus to the left window" },
    { "<C-j>", function() require("smart-splits").move_cursor_down() end, desc = "Move focus to the lower window" },
    { "<C-k>", function() require("smart-splits").move_cursor_up() end, desc = "Move focus to the upper window" },
    { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move focus to the right window" },
  },
  config = function()
    require("smart-splits").setup()
  end,
}
