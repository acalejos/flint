defmodule Flint.Types.Enum do
  use Flint.Type, extends: Ecto.Enum, embed_as: fn _, _ -> :dump end
end
