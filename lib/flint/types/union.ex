defmodule Flint.Types.Union do
  @moduledoc """
  Union type for Ecto. Allows the field to be any of the specified types

  ## Options
  * `:oneof` - Allowed types. Can be any valid `Ecto` type (including custom types). Required.
  * `:eager` - Whether to eagerly cast the field value into the `:oneof` in the order that
  they appear in the list. If `false`, `Flint` will attempt to determine if the value maps to a
  valid `Ecto` type before casting and will prefer that type (if it appears in `:oneof`). Defaults
  to `false`.
  """
  use Ecto.ParameterizedType

  @impl true
  def init(opts) do
    # :schema and :field are implicitly passed by Ecto
    types = Keyword.fetch!(opts, :oneof)
    schema = Keyword.fetch!(opts, :schema)
    field = Keyword.fetch!(opts, :field)
    eager = Keyword.get(opts, :eager, false)

    types = Enum.map(types, &check_field_type!(schema, field, &1, opts))

    %{types: types, eager: eager}
  end

  # TODO: Should this be anything else (or does it matter if we're never expecting to interact with an adapter?)
  @impl true
  def type(_params), do: :any

  @impl true
  def cast(data, %{types: types, eager: true}) do
    Enum.find_value(types, :error, fn type ->
      case Ecto.Type.cast(type, data) do
        :error ->
          false

        other ->
          other
      end
    end)
  end

  def cast(data, %{types: types}) do
    inferred_type = value_type(data)

    cond do
      inferred_type in types ->
        Ecto.Type.cast(inferred_type, data)

      true ->
        cast(data, %{types: types, eager: true})
    end
  end

  @impl true
  def dump(nil, _, _), do: {:ok, nil}

  def dump(value, dumper, _params) do
    if Ecto.Type.composite?(value) do
      dumper.(value)
    else
      {:ok, value}
    end
  end

  @impl true
  def embed_as(_format, _params), do: :dump

  @impl true
  def load(_value, _loader, _params), do: :error

  # From https://github.com/elixir-ecto/ecto/blob/88100b862f69682e4bec4bd11ab8d459346817b0/lib/ecto/schema.ex#L2446

  defp check_field_type!(_mod, name, :datetime, _opts) do
    raise ArgumentError,
          "invalid type :datetime for field #{inspect(name)}. " <>
            "You probably meant to choose one between :naive_datetime " <>
            "(no time zone information) or :utc_datetime (time zone is set to UTC)"
  end

  defp check_field_type!(mod, name, type, opts) do
    cond do
      composite?(type, name) ->
        {outer_type, inner_type} = type
        {outer_type, check_field_type!(mod, name, inner_type, opts)}

      not is_atom(type) ->
        raise ArgumentError, "invalid type #{Ecto.Type.format(type)} for field #{inspect(name)}"

      Ecto.Type.base?(type) ->
        type

      Code.ensure_compiled(type) == {:module, type} ->
        cond do
          function_exported?(type, :type, 0) ->
            type

          function_exported?(type, :type, 1) ->
            Ecto.ParameterizedType.init(type, Keyword.merge(opts, field: name, schema: mod))

          function_exported?(type, :__schema__, 1) ->
            raise ArgumentError,
                  "schema #{inspect(type)} is not a valid type for field #{inspect(name)}." <>
                    " Did you mean to use belongs_to, has_one, has_many, embeds_one, or embeds_many instead?"

          true ->
            raise ArgumentError,
                  "module #{inspect(type)} given as type for field #{inspect(name)} is not an Ecto.Type/Ecto.ParameterizedType"
        end

      true ->
        raise ArgumentError, "unknown type #{inspect(type)} for field #{inspect(name)}"
    end
  end

  defp composite?({composite, _} = type, name) do
    if Ecto.Type.composite?(composite) do
      true
    else
      raise ArgumentError,
            "invalid or unknown composite #{inspect(type)} for field #{inspect(name)}. " <>
              "Did you mean to use :array or :map as first element of the tuple instead?"
    end
  end

  defp composite?(_type, _name), do: false

  defp value_type(%Decimal{}), do: :decimal
  defp value_type(%Time{microsecond: {0, 0}}), do: :time
  defp value_type(%Time{}), do: :time_usec
  defp value_type(%NaiveDateTime{microsecond: {0, 0}}), do: :naive_datetime
  defp value_type(%NaiveDateTime{}), do: :naive_datetime_usec
  defp value_type(%DateTime{microsecond: {0, 0}}), do: :utc_datetime
  defp value_type(%DateTime{}), do: :utc_datetime_usec
  defp value_type(%{}), do: :map
  defp value_type(value) when is_integer(value), do: :integer
  defp value_type(value) when is_float(value), do: :float
  defp value_type(<<_first::utf8, _rest::binary>>), do: :string
  defp value_type(value) when is_binary(value), do: :binary
  defp value_type(value) when is_boolean(value), do: :boolean
  defp value_type([]), do: nil
  defp value_type([item] = value) when is_list(value), do: {:array, value_type(item)}
  defp value_type(_), do: nil
end
