local curl = require("plenary.curl")

local M = {}

M.config = {
  api_key = vim.env.GEMINI_API_KEY,
  api_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
}

local function show_spinner(bufnr)
  local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local i = 1
  local timer = vim.loop.new_timer()

  local function update_spinner()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        timer:stop()
        return
      end

      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "Loading... " .. spinner_chars[i] })
        i = (i % #spinner_chars) + 1
        return true
      else
        timer:stop()
      end
      return false
    end)
  end

  timer:start(100, 100, vim.schedule_wrap(update_spinner))

  return {
    stop = function()
      if timer then
        timer:stop()
        timer:close()
      end
    end,
  }
end

function gemini_complete(prompt, cb2, bufnr)
  local spinner = show_spinner(bufnr)

  vim.notify("Sending request to Gemini API...", vim.log.levels.INFO)

  curl.post(M.config.api_url .. "?key=" .. M.config.api_key, {
    body = vim.fn.json_encode({
      contents = {
        {
          parts = {
            { text = prompt },
          },
        },
      },
    }),
    headers = {
      ["Content-Type"] = "application/json",
    },
    timeout = 0,
    stream = false, -- TODO: figure out how to handle streaming responses
    callback = function(response)
      vim.schedule(function()
        spinner:stop()

        local json = vim.fn.json_decode(response.body)
        local text = json.candidates
          and json.candidates[1]
          and json.candidates[1].content
          and json.candidates[1].content.parts
          and json.candidates[1].content.parts[1]
          and json.candidates[1].content.parts[1].text

        cb2(text)
      end)
    end,
  })
end

function M:check_api_key()
  if not M.config.api_key then
    vim.notify("No API key found. Please set GEMINI_API_KEY in your environment variables.", vim.log.levels.ERROR)
    return false
  end
  return true
end

function open_floating_window()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 80,
    height = 10,
    row = 10,
    col = 10,
    style = "minimal",
    border = "rounded",
    title = "Gemini",
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hello, world!" })
end

local function create_gemini_popup()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create the output buffer (top 2/3, read-only)
  local output_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[output_buf].buftype = "nofile"
  vim.bo[output_buf].modifiable = false
  vim.bo[output_buf].readonly = true

  -- Create the input buffer (bottom 1/3)
  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype = "nofile"
  vim.bo[input_buf].modifiable = true

  -- Create the floating window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  }
  local main_win = vim.api.nvim_open_win(output_buf, true, win_opts)

  -- Split the main window, bottom 1/3 for input
  local split_height = math.floor(height * 2 / 3)
  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    width = width,
    height = height - split_height,
    row = row + split_height,
    col = col,
    style = "minimal",
    border = "single",
  })

  -- Close floating windows on 'q' in normal mode
  vim.api.nvim_buf_set_keymap(
    output_buf,
    "n",
    "q",
    "<cmd>lua vim.api.nvim_win_close(0, true)<CR>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    input_buf,
    "n",
    "q",
    "<cmd>lua vim.api.nvim_win_close(0, true)<CR>",
    { noremap = true, silent = true }
  )

  -- Handle Enter key in input buffer
  vim.api.nvim_buf_set_keymap(input_buf, "n", "<CR>", "<cmd>lua on_submit()<CR>", { noremap = true, silent = true })

  -- Function to handle submission
  function _G.on_submit()
    local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local prompt = table.concat(lines, "\n")

    -- Call `gemini_complete(prompt)`, assuming it returns a response string
    function callback(response)
      response = response or "No response"
      local response_lines = vim.split(response, "\n")
      table.insert(response_lines, 1, "`$> " .. prompt .. "`")

      -- Append response to output buffer
      vim.bo[output_buf].modifiable = true
      vim.bo[output_buf].readonly = false
      vim.api.nvim_buf_set_lines(output_buf, -1, -1, false, response_lines)
      vim.bo[output_buf].filetype = "markdown"
      vim.bo[output_buf].modifiable = false
      vim.bo[output_buf].readonly = true

      -- Clear the input buffer
      vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, {})
    end

    gemini_complete(prompt, callback, input_buf)
  end
end

vim.api.nvim_create_user_command("GeminiPopup", create_gemini_popup, {})

M.open_floating_window = open_floating_window

---------------------------------------------------------------------------------------------------

vim.api.nvim_create_user_command("GeminiComplete", function()
  local gemini = require("mogwai")
  gemini:complete()
end, { nargs = "*", desc = "Get code completion" })

return M
