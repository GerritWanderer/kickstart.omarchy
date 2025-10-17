return {
	"mrjones2014/smart-splits.nvim",
	lazy = false,
	config = function()
		require("smart-splits").setup()

		-- Navigation keymaps
		vim.keymap.set(
			"n",
			"<C-h>",
			require("smart-splits").move_cursor_left,
			{ desc = "Move focus to the left window" }
		)
		vim.keymap.set(
			"n",
			"<C-j>",
			require("smart-splits").move_cursor_down,
			{ desc = "Move focus to the lower window" }
		)
		vim.keymap.set(
			"n",
			"<C-k>",
			require("smart-splits").move_cursor_up,
			{ desc = "Move focus to the upper window" }
		)
		vim.keymap.set(
			"n",
			"<C-l>",
			require("smart-splits").move_cursor_right,
			{ desc = "Move focus to the right window" }
		)
	end,
}
