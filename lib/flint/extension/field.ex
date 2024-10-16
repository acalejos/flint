defmodule Flint.Extension.Field do
  @moduledoc false
  defstruct [
    :name,
    :default,
    :required,
    :validator
  ]
end
