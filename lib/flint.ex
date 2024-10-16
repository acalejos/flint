defmodule Flint do
  @moduledoc """
  #{File.cwd!() |> Path.join("README.md") |> File.read!() |> then(&Regex.run(~r/.*<!-- BEGIN MODULEDOC -->(?P<body>.*)<!-- END MODULEDOC -->.*/s, &1, capture: :all_but_first)) |> hd()}
  """

  def default_extensions do
    [
      Flint.Extensions.Accessible,
      Flint.Extensions.Embedded,
      Flint.Extensions.JSON
    ]
  end
end
