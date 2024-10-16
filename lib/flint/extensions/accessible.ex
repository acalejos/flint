defmodule Flint.Extensions.Accessible do
  @moduledoc """
  An extension to automatically implement the `Access` behaviour for your struct,
  deferring to the `Map` implementation.
  """
  use Flint.Extension

  defmacro __using__(_opts) do
    quote do
      @behaviour Access

      @impl true
      defdelegate fetch(term, key), to: Map
      @impl true
      defdelegate get_and_update(term, key, fun), to: Map
      @impl true
      defdelegate pop(data, key), to: Map
    end
  end
end
