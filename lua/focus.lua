local M = {}

M.state = {
  start_timer = 0,
  end_timer = 0,
  map = {
    size = {
      x = 6,
      y = 6,
    },
  },
  window_config = {
    main = {
      floating = {
        buf = -1,
        win = -1,
      },
      opts = {},
    },
    footer = {
      floating = {
        buf = -1,
        win = -1,
      },
      opts = {},
    },
  },

  hard = false,
  grid = nil,
  positions = nil,
  number_to_cell = nil,
  next_number = 1,
  cpm = 0,
  focus = 0,
  streak = 0,
  correct = 0,
  wrong = 0,
}

local function foreach_float(callback)
  for name, float in pairs(M.state.window_config) do
    callback(name, float)
  end
end

local function generate_grid(width, height)
  local total = width * height
  local digits = tostring(total):len()
  local cell_block = digits + 3

  local nums = {}
  for i = 1, total do
    nums[i] = string.format("%0" .. digits .. "d", i)
  end

  local placement = {}
  local number_to_cell = {}
  local indices = {}
  for i = 1, total do indices[i] = i end

  math.randomseed(os.time())
  for i = total, 2, -1 do
    local j = math.random(1, i)
    indices[i], indices[j] = indices[j], indices[i]
  end
  for cell = 1, total do
    local number = indices[cell]
    placement[cell] = number
    number_to_cell[number] = cell
  end

  local function rep(ch, n) return (n > 0) and string.rep(ch, n) or "" end

  local wseg = digits + 2

  local function top_line()
    local s = "┌"
    for x = 1, width do
      s = s .. rep("─", wseg)
      s = s .. (x < width and "┬" or "┐")
    end
    return s
  end

  local function mid_line()
    local s = "├"
    for x = 1, width do
      s = s .. rep("─", wseg)
      s = s .. (x < width and "┼" or "┤")
    end
    return s
  end

  local function bottom_line()
    local s = "└"
    for x = 1, width do
      s = s .. rep("─", wseg)
      s = s .. (x < width and "┴" or "┘")
    end
    return s
  end

  local lines = {}
  table.insert(lines, top_line())

  local idx = 1
  for r = 1, height do
    local line = "│"
    for c = 1, width do
      line = line .. " " .. nums[placement[idx]] .. " │"
      idx = idx + 1
    end
    table.insert(lines, line)
    if r < height then table.insert(lines, mid_line()) end
  end

  table.insert(lines, bottom_line())

  local meta = {
    digits = digits,
    cell_block = cell_block,
    total = total,
    width = width,
    height = height,
    placement = placement,
    number_to_cell = number_to_cell,
  }

  return lines, #lines[1], #lines, meta
end

local function find_number_positions_in_line(line_text, digits, width)
  local positions = {}
  local search_start = 1
  local found_count = 0
  while true do
    local s, e = string.find(line_text, "%d+", search_start)
    if not s then break end
    local len = e - s + 1

    if len == digits then
      found_count = found_count + 1
      positions[found_count] = { start = s, ["end"] = e }
      if found_count >= width then break end
      search_start = e + 1
    else
      search_start = e + 1
    end
  end
  return positions
end

local function cursor_to_cell(win, row, col0, meta)
  if not meta or not meta.width or not meta.digits then return nil end
  if (row % 2) ~= 0 then return nil end

  local cell_row = row / 2
  if cell_row < 1 or cell_row > meta.height then return nil end

  local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok_buf or not buf or not vim.api.nvim_buf_is_valid(buf) then return nil end
  local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, buf, row - 1, row, false)
  if not ok_lines or not lines or not lines[1] then return nil end
  local line_text = lines[1]

  local positions = find_number_positions_in_line(line_text, meta.digits, meta.width)
  if #positions == 0 then return nil end

  local col = col0 + 1

  for i, pos in ipairs(positions) do
    if col >= pos.start and col <= pos["end"] then
      local cell_x = i
      local cell_index = (cell_row - 1) * meta.width + cell_x
      if cell_index >= 1 and cell_index <= meta.total then
        return cell_index, cell_x, cell_row
      else
        return nil
      end
    end
  end

  return nil
end

local function move_cursor_to_cell(win, cell_x, cell_y, meta)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  if not meta then return end

  cell_x = math.max(1, math.min(meta.width, cell_x))
  cell_y = math.max(1, math.min(meta.height, cell_y))

  local line = cell_y * 2

  local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok_buf or not buf or not vim.api.nvim_buf_is_valid(buf) then
    local start_col_1based = 3 + (cell_x - 1) * meta.cell_block
    local col0 = math.max(0, start_col_1based - 1)
    pcall(vim.api.nvim_win_set_cursor, win, { line, col0 })
    return
  end

  local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, buf, line - 1, line, false)
  local start_col0 = 0
  if ok_lines and lines and lines[1] then
    local line_text = lines[1]
    local positions = find_number_positions_in_line(line_text, meta.digits, meta.width)
    if positions and positions[cell_x] then
      start_col0 = math.max(0, positions[cell_x].start - 1)
    else
      local approx_start = 3 + (cell_x - 1) * (meta.cell_block or (meta.digits + 3))
      local line_len = #line_text
      if approx_start > line_len then
        start_col0 = math.max(0, line_len - 1)
      else
        start_col0 = approx_start - 1
      end
    end
  else
    local approx_start = 3 + (cell_x - 1) * (meta.cell_block or (meta.digits + 3))
    start_col0 = math.max(0, approx_start - 1)
  end

  pcall(vim.api.nvim_win_set_cursor, win, { line, start_col0 })
end

local function get_current_cell_from_win(win, meta)
  if not (win and vim.api.nvim_win_is_valid(win)) then return nil end
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok or not pos then return nil end
  local row, col0 = pos[1], pos[2]
  local cell_index, cell_x, cell_y = cursor_to_cell(win, row, col0, meta)
  if not cell_index then return nil end
  return {
    index = cell_index,
    x = cell_x,
    y = cell_y,
    row = row,
    col0 = col0,
  }
end

M.create_window_config = function()
  local height = vim.o.lines
  local width = vim.o.columns

  local grid_lines, win_w, win_h, meta = generate_grid(M.state.map.size.x, M.state.map.size.y)
  M.state.grid = {
    lines = grid_lines,
    width = win_w,
    height = win_h,
    meta = meta,
  }
  M.state.positions = meta.placement
  M.state.number_to_cell = meta.number_to_cell
  M.state.next_number = 1

  local main_opts = {
    relative = "editor",
    style = 'minimal',
    width = win_w,
    height = win_h,
    col = math.floor((width - win_w) / 2) + meta.cell_block * M.state.map.size.x,
    row = math.floor((height - win_h) / 2),
  }

  local footer_opts = {
    relative = "editor",
    style = 'minimal',
    width = win_w,
    height = 2,
    col = main_opts.col,
    row = main_opts.row + win_h,
    border = nil,
  }

  return {
    main = {
      floating = {
        buf = -1,
        win = -1,
      },
      opts = main_opts,
      enter = true,
    },
    footer = {
      floating = {
        buf = -1,
        win = -1,
      },
      opts = footer_opts,
    },
  }
end

local function buf_set_lines_safe(buf, start, finish, strict_indexing, lines)
  pcall(vim.api.nvim_buf_set_option, buf, "modifiable", true)
  pcall(vim.api.nvim_buf_set_lines, buf, start, finish, strict_indexing, lines)
  pcall(vim.api.nvim_buf_set_option, buf, "modifiable", false)
end

local function update_footer()
  local meta = M.state.grid.meta
  local current = M.state.next_number - 1
  local total = meta.total

  local percent = current / total
  if percent < 0 then percent = 0 end
  if percent > 1 then percent = 1 end

  local bar_width = meta.width * meta.cell_block

  bar_width = math.max(10, bar_width - 4)

  local filled = math.floor(percent * bar_width)
  local empty = bar_width - filled

  local bar = string.rep("█", filled) .. string.rep(" ", empty)

  local line1 = string.format("%s %s %d%%", M.state.next_number, bar, math.floor(percent * 100 + 0.5))

  local buf = M.state.window_config.footer.floating.buf
  if buf and vim.api.nvim_buf_is_valid(buf) then
    buf_set_lines_safe(buf, 0, -1, false, { line1 })
  end
end

local ns_id = vim.api.nvim_create_namespace("focus_highlight")
local function highlight_target()
end

local function set_content()
  local cfg = M.state.window_config
  if not cfg.main or not cfg.main.floating then return end
  local main_buf = cfg.main.floating.buf
  local footer_buf = cfg.footer.floating.buf

  if not (main_buf and vim.api.nvim_buf_is_valid(main_buf)) then return end

  local lines = M.state.grid.lines
  buf_set_lines_safe(main_buf, 0, -1, false, lines)

  if footer_buf and vim.api.nvim_buf_is_valid(footer_buf) then
    update_footer()
  end

  highlight_target()
end

local function highlight_correct_cell(buf, line, start_col, length)
  M.ns_correct = vim.api.nvim_create_namespace("grid_correct")
  vim.api.nvim_buf_set_extmark(buf, M.ns_correct, line, start_col, {
    end_col = start_col + length,
    hl_group = "Substitute",
  })
end

local function restart()
  local s = M.state

  s.correct = 0
  s.wrong = 0
  s.streak = 0
  s.next_number = 1
  s.start_timer = os.time()
  s.end_timer = nil

  if M.ns_correct then
    vim.api.nvim_buf_clear_namespace(
      s.window_config.main.floating.buf,
      M.ns_correct,
      0,
      -1
    )
  end
  if M.ns_highlight then
    vim.api.nvim_buf_clear_namespace(
      s.window_config.main.floating.buf,
      M.ns_highlight,
      0,
      -1
    )
  end

  local grid_lines, win_w, win_h, meta =
      generate_grid(M.state.map.size.x, M.state.map.size.y)

  s.grid = {
    lines = grid_lines,
    width = win_w,
    height = win_h,
    meta = meta,
  }
  s.positions = meta.placement
  s.number_to_cell = meta.number_to_cell

  local buf = s.window_config.main.floating.buf
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, grid_lines)

  update_footer()

  highlight_target()

  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end


local function check_selection()
  local s = M.state
  if not s.grid or not s.grid.meta then return end
  local meta = s.grid.meta
  local win = s.window_config.main.floating.win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end

  local current = get_current_cell_from_win(win, meta)
  if not current then
    vim.api.nvim_echo({ { "No number under cursor", "WarningMsg" } }, false, {})
    s.wrong = s.wrong + 1
    s.streak = 0
    update_footer()
    return
  end

  local cell_index = current.index
  local number_here = s.positions[cell_index]
  if not number_here then
    s.wrong = s.wrong + 1
    s.streak = 0
    update_footer()
    return
  end

  if number_here == s.next_number then
    s.correct = s.correct + 1
    s.streak = s.streak + 1
    s.next_number = s.next_number + 1

    local cell_x = current.x
    local cell_y = current.y

    local line_idx = cell_y * 2 - 1
    local row_text = vim.api.nvim_buf_get_lines(s.window_config.main.floating.buf, line_idx, line_idx + 1, false)[1]
    if row_text then
      local start_col = 2 + (cell_x - 1) * meta.cell_block + 1
      local num_s = string.format("%0" .. meta.digits .. "d", number_here)
      local prefix = row_text:sub(1, start_col - 1)
      local suffix = row_text:sub(start_col + #num_s)
      local replaced = prefix .. string.rep("-", #num_s) .. suffix
      local newrow = replaced
      pcall(vim.api.nvim_buf_set_lines, s.window_config.main.floating.buf, line_idx, line_idx + 1, false, { newrow })
      s.positions[cell_index] = nil


      if not M.state.hard then
        highlight_correct_cell(
          s.window_config.main.floating.buf,
          line_idx,
          current.col0,
          #num_s
        )
      end
    end


    s.end_timer = os.time()
    update_footer()
    highlight_target()

    if s.next_number > meta.total then
      local total_time = os.difftime(os.time(), s.start_timer)
      vim.api.nvim_echo(
        { { string.format("Completed! Time: %d sec | Correct: %d | Wrong: %d", total_time, s.correct, s.wrong), "Title" } },
        false, {}
      )
      restart()
    end
  else
    s.wrong = s.wrong + 1
    s.streak = 0
    update_footer()
    vim.api.nvim_echo({ { string.format("Wrong number. Need %d next.", s.next_number), "WarningMsg" } }, false, {})
  end
end

local function move_by_cells(dx, dy)
  local s = M.state
  if not s.grid then return end
  local meta = s.grid.meta
  local win = s.window_config.main.floating.win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end

  local current = get_current_cell_from_win(win, meta)
  if not current then
    move_cursor_to_cell(win, 1, 1, meta)
    return
  end

  local cx = current.x + dx
  local cy = current.y + dy
  cx = math.max(1, math.min(meta.width, cx))
  cy = math.max(1, math.min(meta.height, cy))
  move_cursor_to_cell(win, cx, cy, meta)
end

local function exit_window()
  foreach_float(function(_, float)
    pcall(function()
      if float.floating and float.floating.win and vim.api.nvim_win_is_valid(float.floating.win) then
        vim.api.nvim_win_close(float.floating.win, true)
      end
    end)
  end)
end

local function setup_keymaps()
  local buf = M.state.window_config.main.floating.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end

  vim.keymap.set("n", "<ESC><ESC>", function() exit_window() end, { buffer = buf })
  vim.keymap.set("n", "q", function() exit_window() end, { buffer = buf })
  vim.keymap.set("n", "ZZ", function() exit_window() end, { buffer = buf })

  vim.keymap.set("n", "x", function() check_selection() end, { buffer = buf })
  vim.keymap.set("n", "r", restart, { buffer = buf })

  vim.keymap.set("n", "/", '<cmd>echo "Do not use search!"<CR>', { buffer = buf })
  vim.keymap.set("n", "?", '<cmd>echo "Do not use search!"<CR>', { buffer = buf })
  vim.keymap.set("n", "*", '<cmd>echo "Do not use search!"<CR>', { buffer = buf })
  vim.keymap.set("n", ":", "<cmd>echo 'Use q, double esc or ZZ to exit!'<CR>", { buffer = buf })
  vim.keymap.set("n", "<left>", '<cmd>echo "Use h to move!!"<CR>', { buffer = buf })
  vim.keymap.set("n", "<right>", '<cmd>echo "Use l to move!!"<CR>', { buffer = buf })
  vim.keymap.set("n", "<up>", '<cmd>echo "Use k to move!!"<CR>', { buffer = buf })
  vim.keymap.set("n", "<down>", '<cmd>echo "Use j to move!!"<CR>', { buffer = buf })

  vim.keymap.set("n", "h", function() move_by_cells(-1, 0) end, { buffer = buf })
  vim.keymap.set("n", "l", function() move_by_cells(1, 0) end, { buffer = buf })
  vim.keymap.set("n", "k", function() move_by_cells(0, -1) end, { buffer = buf })
  vim.keymap.set("n", "j", function() move_by_cells(0, 1) end, { buffer = buf })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    callback = function()
      exit_window()
    end,
  })
end

vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("focus-resized", {}),
  callback = function()
    if not M.state.window_config.main.floating.win or not vim.api.nvim_win_is_valid(M.state.window_config.main.floating.win) then
      return
    end

    M.create_window_config()
    exit_window()
    if M.start_focus then
      M.start_focus()
    end
  end,
})

M.start_focus = function()
  M.state.cpm = 0
  M.state.focus = 0
  M.state.streak = 0
  M.state.correct = 0
  M.state.wrong = 0
  M.state.start_timer = os.time()
  M.state.end_timer = 0

  M.state.window_config = M.create_window_config()

  foreach_float(function(name, float)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")

    local win = vim.api.nvim_open_win(bufnr, name == "main" and true or false, float.opts)

    M.state.window_config[name].floating.buf = bufnr
    M.state.window_config[name].floating.win = win

    vim.api.nvim_buf_set_option(bufnr, "filetype", "focus_" .. name)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  end)

  set_content()

  local meta = M.state.grid.meta
  local start_cell = math.random(1, meta.total)
  local cell_x = ((start_cell - 1) % meta.width) + 1
  local cell_y = math.floor((start_cell - 1) / meta.width) + 1
  move_cursor_to_cell(M.state.window_config.main.floating.win, cell_x, cell_y, meta)

  setup_keymaps()
end

vim.api.nvim_create_user_command("Focus", function()
  local win = M.state.window_config.main.floating.win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    M.start_focus()
  else
    exit_window()
  end
end, {})

--- Setup function to configure map size and optional defaults
---@param opts table
M.setup = function(opts)
  opts = opts or {}
  local map_size = opts.map_size or opts.size or opts.map or nil
  if map_size then
    M.state.map.size = {
      x = map_size.x or M.state.map.size.x,
      y = map_size.y or M.state.map.size.y,
    }
  end
  M.state.hard = opts.hard
end

return M
