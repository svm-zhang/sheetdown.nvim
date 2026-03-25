local M = {}

function M.eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual: %s"):format(
      message or "values are not equal",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

function M.ok(value, message)
  if not value then
    error(message or "expected a truthy value")
  end
end

function M.match(text, expected, message)
  if not tostring(text):find(expected, 1, true) then
    error(message or ("expected %q to contain %q"):format(tostring(text), expected))
  end
end

function M.expect_error(fn, expected)
  local ok, err = pcall(fn)
  if ok then
    error("expected an error but the call succeeded")
  end

  if expected and not tostring(err):find(expected, 1, true) then
    error(("expected error containing %q, got %s"):format(expected, tostring(err)))
  end
end

return M
