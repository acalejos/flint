defmodule Flint.Extensions.Typed do
  use Flint.Extension

  option :enforce, required: false, validator: &is_boolean/1
  option :null, default: true, required: false, validator: &is_boolean/1
end
