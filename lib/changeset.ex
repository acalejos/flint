defmodule Flint.Changeset do
  @moduledoc """
  The base `changeset` function defined by `Flint`. `Flint.Changeset` uses the module attributes
  that are collected when using the `Flint.Schema` macros to perform transformations and validations.
  """

  @doc """
  Given a `Flint` (or `Ecto`) schema and params (can be a map, struct of the given schema, or an existing changeset),
  applies all steps of the `Flint.Changeset` to generate a new changeset.

  This function casts all fields (recursively casting all embeds using this same function),
  validates required fields (specified using the bang (`!`) macros exposed by `Flint`),
  outputting the resulting `Ecto.Changeset`.
  """
  def changeset(schema, params \\ %{}, bindings \\ []) do
    module = schema.__struct__
    fields = module.__schema__(:fields) |> MapSet.new()
    embedded_fields = module.__schema__(:embeds) |> MapSet.new()

    params =
      case params do
        %Ecto.Changeset{params: params} -> params
        s when is_struct(s) -> Map.from_struct(params)
        _ -> params
      end

    required = module.__schema__(:required)
    fields = fields |> MapSet.difference(embedded_fields)
    required_embeds = Enum.filter(required, &(&1 in embedded_fields))
    required_fields = Enum.filter(required, &(&1 in fields))

    changeset =
      schema
      |> Ecto.Changeset.cast(params, fields |> MapSet.to_list())

    changeset =
      for field <- embedded_fields, reduce: changeset do
        changeset ->
          changeset
          |> Ecto.Changeset.cast_embed(field,
            required: field in required_embeds,
            with: &changeset(&1, &2, bindings)
          )
      end

    changeset
    |> Ecto.Changeset.validate_required(required_fields)
  end
end
