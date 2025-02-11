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

    inputs =
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
      |> Ecto.Changeset.cast(inputs, fields |> MapSet.to_list())

    extension_names =
      module.__schema__(:extensions)
      |> Enum.map(fn
        {ext, _opts} when is_atom(ext) -> ext
        ext when is_atom(ext) -> ext
      end)

    changeset =
      changeset
      |> Ecto.Changeset.validate_required(required_fields)
      |> then(
        &Enum.reduce(extension_names, &1, fn extension, chst ->
          extension.changeset(chst, bindings)
        end)
      )

    changeset =
      Enum.reduce(embedded_fields, changeset, fn field, chst ->
        Ecto.Changeset.cast_embed(chst, field,
          required: field in required_embeds,
          with: &changeset(&1, &2, bindings ++ to_bindings(chst))
        )
      end)

    # Passthrough virtual field changes
    case params do
      %Ecto.Changeset{changes: changes} ->
        changeset
        |> Ecto.Changeset.change(Map.take(changes, module.__schema__(:virtual_fields)))

      _ ->
        changeset
    end
  end

  def to_bindings(%Ecto.Changeset{changes: %{} = changes}) do
    for {field, chng} <- changes do
      case chng do
        %Ecto.Changeset{} ->
          {field, to_bindings(chng)}

        array when is_list(array) ->
          {field, Enum.map(array, &to_bindings/1)}

        _ ->
          {field, chng}
      end
    end
  end
end
