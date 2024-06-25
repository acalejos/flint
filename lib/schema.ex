defmodule Flint.Schema do
  import Ecto.Changeset
  @error_regex ~r"%{(\w+)}"
  @embeds_one_defaults Application.compile_env(Flint, [:embeds_one],
                         defaults_to_struct: true,
                         on_replace: :delete
                       )
  @embeds_one_bang_defaults Application.compile_env(Flint, [:embeds_one!],
                              defaults_to_struct: false
                            )
  @embeds_many_defaults Application.compile_env(Flint, [:embeds_many], on_replace: :delete)
  @embeds_many_bang_defaults Application.compile_env(Flint, [:embeds_many!], on_replace: :delete)
  @enum_defaults Application.compile_env(Flint, [:enum], embed_as: :dumped)
  defp make_required(module, name) do
    Module.put_attribute(module, :required, name)
  end

  def dump(obj) do
    obj |> Ecto.embedded_dump(:json)
  end

  defmacro field(name, type \\ :string, opts \\ []) do
    opts =
      case type do
        {_, _, [:Ecto, :Enum]} ->
          opts ++ @enum_defaults

        _ ->
          opts
      end

    quote do
      Ecto.Schema.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field!(name, type \\ :string, opts \\ []) do
    make_required(__CALLER__.module, name)

    quote do
      field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro embeds_one(name, schema, opts \\ [])

  defmacro embeds_one(name, schema, do: block) do
    quote do
      Ecto.Schema.embeds_one(unquote(name), unquote(schema), unquote(@embeds_one_defaults),
        do: unquote(block)
      )
    end
  end

  defmacro embeds_one(name, schema, opts) do
    quote do
      Ecto.Schema.embeds_one(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_one_defaults)
      )
    end
  end

  defmacro embeds_one(name, schema, opts, do: block) do
    quote do
      Ecto.Schema.embeds_one(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_one_defaults),
        do: unquote(block)
      )
    end
  end

  defmacro embeds_one!(name, schema, opts \\ []) do
    make_required(__CALLER__.module, name)

    quote do
      embeds_one(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_one_bang_defaults)
      )
    end
  end

  defmacro embeds_many(name, schema, opts \\ [])

  defmacro embeds_many(name, schema, do: block) do
    quote do
      embeds_many(unquote(name), unquote(schema), unquote(@embeds_many_defaults),
        do: unquote(block)
      )
    end
  end

  defmacro embeds_many(name, schema, opts) do
    quote do
      Ecto.Schema.embeds_many(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_many_defaults)
      )
    end
  end

  defmacro embeds_many(name, schema, opts, do: block) do
    quote do
      Ecto.Schema.embeds_many(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_many_defaults),
        do: unquote(block)
      )
    end
  end

  defmacro embeds_many!(name, schema, opts \\ []) do
    make_required(__CALLER__.module, name)

    quote do
      embeds_many(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_many_bang_defaults)
      )
    end
  end

  def changeset(schema, params \\ %{}) do
    module = schema.__struct__
    fields = module.__schema__(:fields) |> MapSet.new()
    embedded_fields = module.__schema__(:embeds) |> MapSet.new()
    params = if is_struct(params), do: Map.from_struct(params), else: params
    required = module.__schema__(:required)

    fields = fields |> MapSet.difference(embedded_fields)

    required_embeds = Enum.filter(required, &(&1 in embedded_fields))

    required_fields = Enum.filter(required, &(&1 in fields))

    changeset =
      schema
      |> cast(params, fields |> MapSet.to_list())

    changeset =
      for field <- embedded_fields, reduce: changeset do
        changeset ->
          changeset
          |> cast_embed(field, required: field in required_embeds)
      end

    changeset |> validate_required(required_fields)
  end

  def new(module, params \\ %{}) do
    apply(module, :changeset, [struct!(module), params])
    |> apply_changes()
  end

  def new!(module, params \\ %{}) do
    changeset = apply(module, :changeset, [struct!(module), params])

    if changeset.valid? do
      apply_changes(changeset)
    else
      message =
        traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(@error_regex, msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)

      raise ArgumentError, "#{inspect(struct!(module, Map.merge(params, message)), pretty: true)}"
    end
  end
end
