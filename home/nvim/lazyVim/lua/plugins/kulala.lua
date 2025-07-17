return {
  "mistweaverco/kulala.nvim",
  ft = "http",
  keys = {
    { "<leader>R", "", desc = "+Rest", ft = "http" },
    { "<leader>Rb", "<cmd>lua require('kulala').scratchpad()<cr>", desc = "Open scratchpad", ft = "http" },
    { "<leader>Rc", "<cmd>lua require('kulala').copy()<cr>", desc = "Copy as cURL", ft = "http" },
    { "<leader>RC", "<cmd>lua require('kulala').from_curl()<cr>", desc = "Paste from curl", ft = "http" },
    {
      "<leader>Rg",
      "<cmd>lua require('kulala').download_graphql_schema()<cr>",
      desc = "Download GraphQL schema",
      ft = "http",
    },
    { "<leader>Ri", "<cmd>lua require('kulala').inspect()<cr>", desc = "Inspect current request", ft = "http" },
    { "<leader>Rn", "<cmd>lua require('kulala').jump_next()<cr>", desc = "Jump to next request", ft = "http" },
    { "<leader>Rp", "<cmd>lua require('kulala').jump_prev()<cr>", desc = "Jump to previous request", ft = "http" },
    { "<leader>Rq", "<cmd>lua require('kulala').close()<cr>", desc = "Close window", ft = "http" },
    { "<leader>Rr", "<cmd>lua require('kulala').replay()<cr>", desc = "Replay the last request", ft = "http" },
    { "<leader>Rs", "<cmd>lua require('kulala').run()<cr>", desc = "Send the request", ft = "http" },
    { "<leader>RS", "<cmd>lua require('kulala').show_stats()<cr>", desc = "Show stats", ft = "http" },
    { "<leader>Rt", "<cmd>lua require('kulala').toggle_view()<cr>", desc = "Toggle headers/body", ft = "http" },
    -- Additional useful keymaps
    { "<leader>Ra", "<cmd>lua require('kulala').run_all()<cr>", desc = "Run all requests", ft = "http" },
    { "<leader>Re", "<cmd>lua require('kulala').set_selected_env()<cr>", desc = "Set environment", ft = "http" },
    { "<leader>Rv", "<cmd>lua require('kulala').search()<cr>", desc = "Search requests", ft = "http" },
  },
  opts = {
    -- Tool paths - these will be automatically detected if in PATH
    curl_path = "curl",
    grpcurl_path = "grpcurl",
    websocat_path = "websocat",
    openssl_path = "openssl",

    -- Environment and request variables scope
    environment_scope = "b", -- buffer scope for better isolation
    default_env = "dev",
    vscode_rest_client_environmentvars = true, -- Enable VSCode compatibility

    -- Request handling
    request_timeout = 30000, -- 30 seconds timeout
    halt_on_error = false, -- Continue running requests on failure

    -- Content type formatters with proper formatting tools
    contenttypes = {
      ["application/json"] = {
        ft = "json",
        formatter = vim.fn.executable("jq") == 1 and { "jq", "." } or nil,
        pathresolver = function(...)
          return require("kulala.parser.jsonpath").parse(...)
        end,
      },
      ["application/xml"] = {
        ft = "xml",
        formatter = vim.fn.executable("xmllint") == 1 and { "xmllint", "--format", "-" } or nil,
        pathresolver = vim.fn.executable("xmllint") == 1 and { "xmllint", "--xpath", "{{path}}", "-" } or nil,
      },
      ["text/html"] = {
        ft = "html",
        formatter = vim.fn.executable("xmllint") == 1 and { "xmllint", "--format", "--html", "-" } or nil,
        pathresolver = nil,
      },
      ["application/yaml"] = {
        ft = "yaml",
        formatter = vim.fn.executable("yq") == 1 and { "yq", "." } or nil,
        pathresolver = nil,
      },
    },

    -- UI Configuration
    ui = {
      display_mode = "split",
      split_direction = "vertical",
      win_opts = {},
      default_view = "body",
      winbar = true,
      default_winbar_panes = {
        "body",
        "headers",
        "headers_body",
        "verbose",
        "script_output",
        "stats",
        "report",
        "help",
      },

      -- Variable info display
      show_variable_info_text = "float",

      -- Icons configuration
      show_icons = "on_request",
      icons = {
        inlay = {
          loading = "⏳",
          done = "✅",
          error = "❌",
        },
        lualine = "🐼",
        textHighlight = "WarningMsg",
      },

      -- Request summary and output
      show_request_summary = true,
      disable_script_print_output = false,

      -- Report configuration
      report = {
        show_script_output = true,
        show_asserts_output = true,
        show_summary = true,
        headersHighlight = "Special",
        successHighlight = "String",
        errorHighlight = "Error",
      },

      -- Scratchpad with better default template
      scratchpad_default_contents = {
        "### Variables",
        "@baseUrl=https://httpbin.org",
        "@token=your_token_here",
        "",
        "### GET Request",
        "GET {{baseUrl}}/get HTTP/1.1",
        "Accept: application/json",
        "",
        "### POST Request",
        "POST {{baseUrl}}/post HTTP/1.1",
        "Accept: application/json",
        "Content-Type: application/json",
        "",
        "{",
        '  "name": "test",',
        '  "value": "example"',
        "}",
        "",
        "### PUT Request with Auth",
        "PUT {{baseUrl}}/put HTTP/1.1",
        "Accept: application/json",
        "Content-Type: application/json",
        "Authorization: Bearer {{token}}",
        "",
        "{",
        '  "id": 1,',
        '  "updated": true',
        "}",
      },

      -- Disable news popup
      disable_news_popup = true,

      -- Enable autocompletion
      autocomplete = true,

      -- Enable Lua syntax highlighting in HTTP scripts
      lua_syntax_hl = true,
    },

    -- Debug mode (set to 0 for production, 1-3 for increasing verbosity)
    debug = 0,

    -- Disable global keymaps since we're using LazyVim's key configuration
    global_keymaps = false,

    -- Enable kulala UI keymaps
    kulala_keymaps = true,

    -- Additional cURL options for better debugging and formatting
    additional_curl_options = {
      "--compressed", -- Enable compression
      "--location", -- Follow redirects
      "--max-redirs",
      "10", -- Limit redirects
      "--connect-timeout",
      "10", -- Connection timeout
    },
  },
  config = function(_, opts)
    require("kulala").setup(opts)

    -- Auto-format JSON responses
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "json",
      callback = function()
        if vim.bo.buftype == "nofile" and vim.fn.expand("%:t"):match("kulala") then
          vim.opt_local.formatprg = "jq ."
        end
      end,
    })

    -- Better syntax highlighting for .http files
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "http",
      callback = function()
        vim.opt_local.commentstring = "# %s"
        vim.opt_local.foldmethod = "expr"
        vim.opt_local.foldexpr = "v:lnum==1?0:getline(v:lnum)=~'^###'?'>1':1"
        vim.opt_local.foldtext = "getline(v:foldstart)"
      end,
    })
  end,
}
