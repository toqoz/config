vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<CR>")

-- Emacs-like keybinds in command-line mode
vim.keymap.set("c", "<C-A>", "<Home>")
vim.keymap.set("c", "<C-E>", "<End>")
vim.keymap.set("c", "<C-F>", "<Right>")
vim.keymap.set("c", "<C-B>", "<Left>")
vim.keymap.set("c", "<C-P>", "<Up>")
vim.keymap.set("c", "<C-N>", "<Down>")
vim.keymap.set("c", "<C-K>", [[<C-\>e getcmdpos() == 1 ? '' : getcmdline()[:getcmdpos()-2]<CR>]])
