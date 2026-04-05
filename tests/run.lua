local modules = {
	"tests.spec.path_spec",
	"tests.spec.columns_spec",
	"tests.spec.reader_spec",
	"tests.spec.dialect_spec",
	"tests.spec.table_spec",
	"tests.spec.selection_spec",
	"tests.spec.ui_state_spec",
	"tests.spec.ui_session_spec",
	"tests.spec.ui_snacks_spec",
	"tests.spec.ui_routing_spec",
	"tests.spec.commands_lifecycle_spec",
	"tests.spec.integration_spec",
}

local total = 0
local failed = 0

for _, module_name in ipairs(modules) do
	local cases = require(module_name)
	for _, case in ipairs(cases) do
		total = total + 1
		local ok, err = xpcall(case.run, debug.traceback)
		if ok then
			print(("ok - %s"):format(case.name))
		else
			failed = failed + 1
			print(("not ok - %s"):format(case.name))
			print(err)
		end
	end
end

print(("Executed %d tests"):format(total))

if failed > 0 then
	error(("%d tests failed"):format(failed))
end
