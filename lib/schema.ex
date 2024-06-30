defmodule Flint.Schema do
  require Logger
  import Ecto.Changeset
  @error_regex ~r"%{(\w+)}"
  @required_with_default_warning """
  You are setting a default value for a field marked as required (!).
  Be aware that validating required variables happens after casting,
  and casting will replace any missing fields with their defaults (if specified).
  These will never fail the `required` validation.
  """
  @embeds_one_defaults Application.compile_env(Flint, [:embeds_one],
                         defaults_to_struct: true,
                         on_replace: :delete
                       )
  @embeds_one_bang_defaults Application.compile_env(Flint, [:embeds_one!],
                              defaults_to_struct: false,
                              on_replace: :delete
                            )
  @embeds_many_defaults Application.compile_env(Flint, [:embeds_many], on_replace: :delete)
  @embeds_many_bang_defaults Application.compile_env(Flint, [:embeds_many!], on_replace: :delete)
  @enum_defaults Application.compile_env(Flint, [:enum], embed_as: :dumped)
  @validation_opts [
    :greater_than,
    :less_than,
    :less_than_or_equal_to,
    :greater_than_or_equal_to,
    :equal_to,
    :not_equal_to,
    :format,
    :subset_of,
    :in,
    :not_in,
    :is,
    :min,
    :max,
    :count
  ]
  @default_aliases [
    lt: :less_than,
    gt: :greater_than,
    le: :less_than_or_equal_to,
    ge: :greater_than_or_equal_to,
    eq: :equal_to,
    neq: :not_equal_to
  ]
  @aliases Application.compile_env(Flint, :aliases, @default_aliases)
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

    {validator_opts, opts} = Keyword.split(opts, @validation_opts)
    {alias_opts, opts} = Keyword.split(opts, Keyword.keys(@aliases))

    validator_opts =
      validator_opts ++
        Enum.map(alias_opts, fn {als, opt} ->
          mapped = Keyword.get(@aliases, als)

          unless mapped in @validation_opts do
            raise ArgumentError,
                  "Alias #{inspect(als)} in field #{inspect(name)} mapped to invalid option #{inspect(mapped)}. Must be mapped to a value in #{inspect(@validation_opts)}"
          end

          {mapped, opt}
        end)

    # TODO: validate_validations!(type, validator_opts)
    # Not sure how horrible it would be to implement compile-time checks on these
    if length(validator_opts) != 0,
      do: Module.put_attribute(__CALLER__.module, :validations, {name, validator_opts})

    quote do
      Ecto.Schema.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field!(name, type \\ :string, opts \\ []) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro embeds_one(name, schema, opts \\ [])

  defmacro embeds_one(name, schema, do: block) do
    quote do
      embeds_one(unquote(name), unquote(schema), unquote(@embeds_one_defaults), do: unquote(block))
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
    schema = expand_nested_module_alias(schema, __CALLER__)

    quote do
      {schema, opts} =
        Flint.Schema.__embeds_module__(
          __ENV__,
          unquote(schema),
          unquote(opts) ++ unquote(@embeds_one_defaults),
          unquote(Macro.escape(block))
        )

      Ecto.Schema.__embeds_one__(__MODULE__, unquote(name), schema, opts)
    end
  end

  defmacro embeds_one!(name, schema, opts \\ [])

  defmacro embeds_one!(name, schema, do: block) do
    make_required(__CALLER__.module, name)

    quote do
      embeds_one(
        unquote(name),
        unquote(schema),
        unquote(@embeds_one_bang_defaults),
        do: unquote(block)
      )
    end
  end

  defmacro embeds_one!(name, schema, opts) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      embeds_one(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_one_bang_defaults)
      )
    end
  end

  defmacro embeds_one!(name, schema, opts, do: block) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      embeds_one(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_one_bang_defaults),
        do: unquote(block)
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
    schema = expand_nested_module_alias(schema, __CALLER__)

    quote do
      {schema, opts} =
        Flint.Schema.__embeds_module__(
          __ENV__,
          unquote(schema),
          unquote(opts) ++ unquote(@embeds_many_bang_defaults),
          unquote(Macro.escape(block))
        )

      Ecto.Schema.__embeds_many__(__MODULE__, unquote(name), schema, opts)
    end
  end

  defmacro embeds_many!(name, schema, opts \\ [])

  defmacro embeds_many!(name, schema, do: block) do
    make_required(__CALLER__.module, name)

    quote do
      embeds_many(
        unquote(name),
        unquote(schema),
        unquote(@embeds_many_bang_defaults),
        do: unquote(block)
      )
    end
  end

  defmacro embeds_many!(name, schema, opts) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      embeds_many(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_many_bang_defaults)
      )
    end
  end

  defmacro embeds_many!(name, schema, opts, do: block) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      embeds_many(
        unquote(name),
        unquote(schema),
        unquote(opts) ++ unquote(@embeds_many_bang_defaults),
        do: unquote(block)
      )
    end
  end

  def __embeds_module__(env, module, opts, block) do
    {pk, opts} = Keyword.pop(opts, :primary_key, false)

    block =
      quote do
        use Flint,
          primary_key: unquote(Macro.escape(pk)),
          schema: [
            unquote(block)
          ]
      end

    Module.create(module, block, env)
    {module, opts}
  end

  def validate_fields(changeset, bindings \\ []) do
    module = changeset.data.__struct__

    all_validations = module.__schema__(:validations)

    for {field, validations} <- all_validations, reduce: changeset do
      changeset ->
        validations =
          validations
          |> Enum.map(fn {k, v} ->
            {result, _bindings} = Code.eval_quoted(v, bindings, __ENV__)
            {k, result}
          end)

        {validate_length_args, validations} =
          Keyword.split(validations, [:is, :min, :max, :count])

        {validate_number_args, validations} =
          Keyword.split(validations, [
            :less_than,
            :greater_than,
            :less_than_or_equal_to,
            :greater_than_or_equal_to,
            :equal_to,
            :not_equal_to
          ])

        {validate_subset_arg, validations} = Keyword.pop(validations, :subset_of)
        {validate_inclusion_arg, validations} = Keyword.pop(validations, :in)
        {validate_exclusion_arg, validations} = Keyword.pop(validations, :not_in)
        {validate_format_arg, _validations} = Keyword.pop(validations, :format)

        validation_args = [
          validate_inclusion: validate_inclusion_arg,
          validate_exclusion: validate_exclusion_arg,
          validate_number: validate_number_args,
          validate_length: validate_length_args,
          validate_format: validate_format_arg,
          validate_subset: validate_subset_arg
        ]

        Enum.reduce(validation_args, changeset, fn
          {_func, nil}, chngset ->
            chngset

          {_func, []}, chngset ->
            chngset

          {func, arg}, chngset ->
            apply(Ecto.Changeset, func, [chngset, field, arg])
        end)
    end
  end

  def changeset(schema, params \\ %{}, bindings \\ []) do
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

    changeset
    |> validate_required(required_fields)
    |> validate_fields(bindings)
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

  defmacro embedded_schema(do: block) do
    quote do
      Ecto.Schema.embedded_schema do
        import Ecto.Schema,
          except: [
            embeds_one: 2,
            embeds_one: 3,
            embeds_one: 4,
            embeds_many: 2,
            embeds_many: 3,
            embeds_many: 4,
            field: 1,
            field: 2,
            field: 3
          ]

        import Flint.Schema

        unquote(block)
      end
    end
  end

  # From https://github.com/elixir-ecto/ecto/blob/1918cdc93d5543c861682fdfb4105a35d21135cc/lib/ecto/schema.ex#L2532
  defp expand_nested_module_alias({:__aliases__, _, [Elixir, _ | _] = alias}, _env),
    do: Module.concat(alias)

  defp expand_nested_module_alias({:__aliases__, _, [h | t]}, env) when is_atom(h),
    do: Module.concat([env.module, h | t])

  defp expand_nested_module_alias(other, _env), do: other
end
