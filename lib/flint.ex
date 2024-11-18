defmodule Flint do
  @moduledoc """
  #{File.cwd!() |> Path.join("README.md") |> File.read!() |> then(&Regex.run(~r/.*<!-- BEGIN MODULEDOC -->(?P<body>.*)<!-- END MODULEDOC -->.*/s, &1, capture: :all_but_first)) |> hd()}
  """

  def default_extensions(opts \\ []) do
    opts = Keyword.validate!(opts, [:except, :only])

    if opts[:except] && opts[:only],
      do: raise(ArgumentError, "Cannot specify both `:only` and `:except` options.")

    defaults =
      [
        Flint.Extensions.Block,
        if(Code.ensure_loaded?(TypedEctoSchema), do: Flint.Extensions.Typed),
        Flint.Extensions.PreTransforms,
        Flint.Extensions.When,
        Flint.Extensions.EctoValidations,
        Flint.Extensions.PostTransforms,
        Flint.Extensions.Accessible,
        Flint.Extensions.Embedded,
        Flint.Extensions.JSON
      ]
      |> Enum.filter(& &1)

    cond do
      opts[:only] ->
        defaults
        |> Enum.filter(fn mod ->
          aliased =
            Module.split(mod)
            |> Enum.reverse()
            |> hd

          mod in opts[:only] || Module.concat([aliased]) in opts[:only]
        end)

      opts[:except] ->
        defaults
        |> Enum.reject(fn mod ->
          aliased =
            Module.split(mod)
            |> Enum.reverse()
            |> hd

          mod in opts[:except] || Module.concat([aliased]) in opts[:except]
        end)

      true ->
        defaults
    end
  end
end
