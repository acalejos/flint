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

  @embeds_one_defaults Application.compile_env(:flint, [:embeds_one],
                         defaults_to_struct: true,
                         on_replace: :delete
                       )
  @embeds_one_bang_defaults Application.compile_env(:flint, [:embeds_one!],
                              defaults_to_struct: false,
                              on_replace: :delete
                            )
  @embeds_many_defaults Application.compile_env(:flint, [:embeds_many], on_replace: :delete)
  @embeds_many_bang_defaults Application.compile_env(:flint, [:embeds_many!], on_replace: :delete)
  @enum_defaults Application.compile_env(:flint, [:enum], embed_as: :dumped)
  @field_opts [
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
    :count,
    :when,
    :block,
    :derive,
    :map
  ]
  @default_aliases [
    lt: :less_than,
    gt: :greater_than,
    le: :less_than_or_equal_to,
    ge: :greater_than_or_equal_to,
    eq: :equal_to,
    ne: :not_equal_to
  ]
  @aliases Application.compile_env(:flint, :aliases, @default_aliases)

  # I think this is the best way to mimic the parent environment to let you write expressions
  # as though they are taking place inside the parent schema.
  # I considered altering the `embedded_schema` macro to do these imports, but it's being
  # defined while the parent schema is being defined and it will not be available yet
  def __after_compile__(env, _bytecode) do
    imports =
      (env.functions ++ env.macros)
      |> Enum.group_by(fn {module, _} -> module end)
      |> Enum.map(fn {module, lists} ->
        items =
          lists
          |> Enum.flat_map(fn {_, items} -> items end)
          # Remove duplicates if any
          |> Enum.uniq()

        quote do
          import unquote(module), only: unquote(items)
        end
      end)

    contents =
      quote do
        def env do
          import unquote(env.module)
          (unquote_splicing(imports))
          __ENV__
        end
      end

    Module.concat(env.module, Env)
    |> Module.create(contents, Macro.Env.location(env))
  end

  defp make_required(module, name) do
    Module.put_attribute(module, :required, name)
  end

  def dump(obj) do
    obj |> Ecto.embedded_dump(:json)
  end

  defmacro field(name, type \\ :string, opts \\ [])

  defmacro field(name, type, do: block) when is_list(block) do
    quote do
      field(unquote(name), unquote(type), [], do: unquote(block))
    end
  end

  defmacro field(_name, _type, do: _block),
    do:
      raise(
        ArgumentError,
        "Bad expression in `field do:`. All clauses should be of the format `condition` -> `Error Message`"
      )

  defmacro field(name, type, opts) do
    opts =
      case type do
        {_, _, [:Ecto, :Enum]} ->
          opts ++ @enum_defaults

        _ ->
          opts
      end

    {validator_opts, opts} = Keyword.split(opts, @field_opts)
    {alias_opts, opts} = Keyword.split(opts, Keyword.keys(@aliases))

    validator_opts =
      validator_opts ++
        Enum.map(alias_opts, fn {als, opt} ->
          mapped = Keyword.get(@aliases, als)

          unless mapped in @field_opts do
            raise ArgumentError,
                  "Alias #{inspect(als)} in field #{inspect(name)} mapped to invalid option #{inspect(mapped)}. Must be mapped to a value in #{inspect(@field_opts)}"
          end

          {mapped, opt}
        end)

    # TODO: validate_validations!(type, validator_opts)
    # Not sure how horrible it would be to implement compile-time checks on these
    if length(validator_opts) != 0,
      do:
        Module.put_attribute(
          __CALLER__.module,
          :validations,
          {name, validator_opts}
        )

    quote do
      Ecto.Schema.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field(name, type, opts, do: block) do
    block =
      block
      |> Enum.map(fn
        {:->, _, [[left], right]} ->
          {left, right}

        _ ->
          raise ArgumentError,
                "Bad expression in `field do:`. All clauses should be of the format `condition` -> `Error Message`"
      end)

    opts = [{:block, block} | opts]

    quote do
      field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field!(name, type \\ :string, opts \\ [])

  defmacro field!(name, type, do: block) do
    quote do
      field!(unquote(name), unquote(type), [], do: unquote(block))
    end
  end

  defmacro field!(name, type, opts) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field!(name, type, opts, do: block) do
    if Keyword.has_key?(opts, :default),
      do: Logger.warning(@required_with_default_warning)

    make_required(__CALLER__.module, name)

    quote do
      field(unquote(name), unquote(type), unquote(opts), do: unquote(block))
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
          env,
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
          env,
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
    # This env is setup to mimic the "parent" module's environment
    env = Module.concat(module, Env) |> apply(:env, [])

    all_validations = module.__schema__(:validations)

    for {field, validations} <- all_validations, reduce: changeset do
      changeset ->
        {derived_expression, validations} = Keyword.pop(validations, :derive)
        {map_expression, validations} = Keyword.pop(validations, :map)
        {block, validations} = Keyword.pop(validations, :block, [])

        bindings = bindings ++ Enum.into(changeset.changes, [])

        {changeset, bindings} =
          if derived_expression do
            {derived_value, _bindings} = Code.eval_quoted(derived_expression, bindings, env)

            derived_value =
              if is_function(derived_value) do
                case :erlang.fun_info(derived_value)[:arity] do
                  0 ->
                    apply(derived_value, [])

                  1 when not is_nil(field) ->
                    apply(derived_value, [
                      Ecto.Changeset.fetch_change!(changeset, field)
                    ])

                  _ ->
                    raise ArgumentError,
                          "Anonymous functions provided to `:derive` must be either 0-arity or an input value for the field must be provided."
                end
              else
                derived_value
              end

            {Ecto.Changeset.put_change(changeset, field, derived_value),
             Keyword.put(bindings, field, derived_value)}
          else
            {changeset, bindings}
          end

        {when_condition, validations} = Keyword.pop(validations, :when)

        validations =
          validations
          |> Enum.map(fn
            {k, v} ->
              {result, _bindings} = Code.eval_quoted(v, bindings, env)
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

        changeset =
          Enum.reduce(validation_args, changeset, fn
            {_func, nil}, chngset ->
              chngset

            {_func, []}, chngset ->
              chngset

            {func, arg}, chngset ->
              apply(Ecto.Changeset, func, [chngset, field, arg])
          end)

        {validate_when_condition, _bindings} =
          try do
            Code.eval_quoted(
              when_condition,
              bindings,
              env
            )
          rescue
            _ ->
              {false, nil}
          end

        if validate_when_condition do
          changeset
        else
          Ecto.Changeset.add_error(changeset, field, "Failed `:when` validation")
        end

        changeset =
          block
          |> Enum.with_index()
          |> Enum.reduce(changeset, fn
            {{quoted_condition, quoted_err}, index}, chngset ->
              try do
                {invalid?, _bindings} = Code.eval_quoted(quoted_condition, bindings, env)

                invalid? =
                  if is_function(invalid?) do
                    case :erlang.fun_info(invalid?)[:arity] do
                      0 ->
                        apply(invalid?, [])

                      1 when not is_nil(field) ->
                        apply(invalid?, [Ecto.Changeset.fetch_change!(changeset, field)])

                      _ ->
                        raise ArgumentError,
                              "Anonymous functions in validation clause must be either 0-arity or an input value for the field must be provided."
                    end
                  else
                    invalid?
                  end

                {err_msg, _bindings} = Code.eval_quoted(quoted_err, bindings, env)

                if invalid? do
                  Ecto.Changeset.add_error(chngset, field, err_msg,
                    validation: :block,
                    clause: index + 1
                  )
                else
                  chngset
                end
              rescue
                _ ->
                  Ecto.Changeset.add_error(
                    chngset,
                    field,
                    "Error evaluating expression in Clause ##{index + 1} of `do:` block"
                  )
              end
          end)

        if is_nil(map_expression) do
          changeset
        else
          {mapped, _bindings} = Code.eval_quoted(map_expression, bindings, env)

          mapped =
            if is_function(mapped) do
              case :erlang.fun_info(mapped)[:arity] do
                1 when not is_nil(field) ->
                  apply(mapped, [Ecto.Changeset.fetch_change!(changeset, field)])

                1 when is_nil(field) ->
                  nil

                _ ->
                  raise ArgumentError,
                        ":map option only accepts arity-1 anonymous function"
              end
            else
              mapped
            end

          Ecto.Changeset.put_change(changeset, field, mapped)
        end
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

    # TODO This should look more like:
    # changeset
    # |> validate_required(required_fields)
    # |> apply_derives()
    # |> validate_fields(bindings)
    # |> apply_maps()

    changeset
    |> validate_required(required_fields)
    |> validate_fields(bindings)
  end

  def new(module, params \\ %{}, bindings \\ []) do
    apply(module, :changeset, [struct!(module), params, bindings])
    |> apply_changes()
  end

  def new!(module, params \\ %{}, bindings \\ []) do
    changeset = apply(module, :changeset, [struct!(module), params, bindings])

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
