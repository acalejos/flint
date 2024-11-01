defmodule Flint.Extension.Entity do
  @moduledoc false
  defstruct [
    :name,
    type: :string,
    required: false,
    opts: []
  ]
end
