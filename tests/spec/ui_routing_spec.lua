local helpers = require("tests.helpers")
local ui_helpers = require("tests.ui_helpers")

return {
	{
		name = "ui.prompt falls back to the vim.ui flow when snacks is unavailable in auto mode",
		run = function()
			ui_helpers.unload("sheetdown.ui")

			ui_helpers.with_module("sheetdown.ui_fallback", {
				prompt = function(headers, config, on_done)
					helpers.eq(headers, { "name" })
					helpers.eq(config.ui.backend, "auto")
					on_done({ ok = true }, nil)
				end,
			}, function()
				local ui = require("sheetdown.ui")
				local called = false

				ui.prompt({ "name" }, { ui = { backend = "auto" } }, function(result, err)
					called = true
					helpers.eq(err, nil)
					helpers.eq(result, { ok = true })
				end)

				helpers.ok(called)
			end)

			ui_helpers.unload("sheetdown.ui")
		end,
	},
	{
		name = "ui.prompt accepts the explicit fallback backend name",
		run = function()
			ui_helpers.unload("sheetdown.ui")

			ui_helpers.with_module("sheetdown.ui_fallback", {
				prompt = function(headers, config, on_done)
					helpers.eq(headers, { "name" })
					helpers.eq(config.ui.backend, "fallback")
					on_done({ ok = "fallback" }, nil)
				end,
			}, function()
				local ui = require("sheetdown.ui")
				local called = false

				ui.prompt(
					{ "name" },
					{ ui = { backend = "fallback" } },
					function(result, err)
						called = true
						helpers.eq(err, nil)
						helpers.eq(result, { ok = "fallback" })
					end
				)

				helpers.ok(called)
			end)

			ui_helpers.unload("sheetdown.ui")
		end,
	},
	{
		name = "ui.prompt routes to the snacks backend when snacks is available in auto mode",
		run = function()
			ui_helpers.unload("sheetdown.ui")

			ui_helpers.with_module("snacks", {}, function()
				ui_helpers.with_module("sheetdown.ui_snacks", {
					prompt = function(headers, config, on_done)
						helpers.eq(headers, { "name" })
						helpers.eq(config.ui.backend, "auto")
						on_done({ ok = "snacks" }, nil)
					end,
				}, function()
					local ui = require("sheetdown.ui")
					local called = false

					ui.prompt(
						{ "name" },
						{ ui = { backend = "auto" } },
						function(result, err)
							called = true
							helpers.eq(err, nil)
							helpers.eq(result, { ok = "snacks" })
						end
					)

					helpers.ok(called)
				end)
			end)

			ui_helpers.unload("sheetdown.ui")
		end,
	},
	{
		name = "ui.prompt reports a clear error when snacks backend is explicitly requested but unavailable",
		run = function()
			ui_helpers.unload("sheetdown.ui")
			ui_helpers.unload("snacks")

			local ui = require("sheetdown.ui")
			local received_error

			ui.prompt({ "name" }, { ui = { backend = "snacks" } }, function(_, err)
				received_error = err
			end)

			helpers.match(received_error, "snacks.nvim UI backend requested")
			ui_helpers.unload("sheetdown.ui")
		end,
	},
}
