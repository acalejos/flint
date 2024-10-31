defmodule Flint.Extension.Entity do
  defstruct [
    :name,
    type: :string,
    required: false,
    opts: []
  ]
end
