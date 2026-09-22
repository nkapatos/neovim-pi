std = "luajit+busted"
max_line_length = false
-- `vim` is writable (`vim.g.*` is set on load); a read-only global would flag
-- those assignments as setting read-only fields.
globals = { "vim" }
