defmodule Flint.Schema do
  @moduledoc """
  `Flint.Schema` provides custom implementations of certain `Ecto` `embedded_schema` DSL keywords.

  When you `use Flint`, all of these definitions are imported into the module and override the default
  `Ecto.Schema` implementations. You should not have to directly interact with this module.
  """
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
    :count,
    :when,
    :block
  ]
  @pre_transform_opts [
    :derive
  ]
  @post_transform_opts [
    :map
  ]
  @field_opts @validation_opts ++ @pre_transform_opts ++ @post_transform_opts
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

  @doc """
  Dumps the JSON representation of the given schema
  """
  def dump(obj) do
    obj |> Ecto.embedded_dump(:json)
  end

  @doc """
  Wraps `Ecto`'s `field` macro to accept additional options which are consumed by `Flint.Pipeline`.

  `Flint` options that are passed to `field` are stripped by `Flint` before passing them to `Ecto.Schema.field` and
  stored in module attributed for the schema's module.

  If no `Flint`-specific options or features are used, this acts the same as `Ecto.Schema.field`.
  """
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

    {field_opts, opts} = Keyword.split(opts, @field_opts)
    {alias_opts, opts} = Keyword.split(opts, Keyword.keys(@aliases))

    field_opts =
      field_opts ++
        Enum.map(alias_opts, fn {als, opt} ->
          mapped = Keyword.get(@aliases, als)

          unless mapped in @field_opts do
            raise ArgumentError,
                  "Alias #{inspect(als)} in field #{inspect(name)} mapped to invalid option #{inspect(mapped)}. Must be mapped to a value in #{inspect(@field_opts)}"
          end

          {mapped, opt}
        end)

    {validator_opts, field_opts} = Keyword.split(field_opts, @validation_opts)
    {pre_transform_opts, field_opts} = Keyword.split(field_opts, @pre_transform_opts)
    {post_transform_opts, _field_opts} = Keyword.split(field_opts, @post_transform_opts)

    for {k, v} <- [
          pre_transforms: pre_transform_opts,
          validations: validator_opts,
          post_transforms: post_transform_opts
        ],
        length(v) != 0 do
      Module.put_attribute(
        __CALLER__.module,
        k,
        {name, v}
      )
    end

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

  @doc """
  Marks a field as required by storing metadata in a module attribute, then calls `Flint.Schema.field`.

  The metadata tracking is not enforced at the schema / struct level (eg. through enforced keys), but rather
  at the schema validation level (through something such as `Flint.Pipeline.changeset`).
  """
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

  @doc """
  Wraps `Ecto`'s `embeds_one` macro to accept additional options which are consumed by `Flint.Pipeline`.

  `Flint` options that are passed to `embeds_one` are stripped by `Flint` before passing them to `Ecto.Schema.embeds_one` and
  stored in module attributed for the schema's module.

  The following default options are passed to `Flint.Schema.embeds_one` and can be overriden at the `Application` level or at the
  local call level.

  ## Default Options

  ```elixir
  defaults_to_struct: true,
  on_replace: :delete
  ```
  """
  defmacro embeds_one(name, schema, opts \\ [])

  defmacro embeds_one(name, schema, do: block) do
    quote do
      embeds_one(unquote(name), unquote(schema), unquote(@embeds_one_defaults),
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

  @doc """
  Marks an embeds_one field as required by storing metadata in a module attribute, then calls `Flint.Schema.embeds_one`.

  The metadata tracking is not enforced at the schema / struct level (eg. through enforced keys), but rather
  at the schema validation level (through something such as `Flint.Pipeline.changeset`).

  The following default options are passed to `Flint.Schema.embeds_one!` and can be overriden at the `Application` level or at the
  local call level.

  ## Default Options

  ```elixir
  on_replace: :delete
  ```
  """
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

  @doc """
  Wraps `Ecto`'s `embeds_many` macro to accept additional options which are consumed by `Flint.Pipeline`.

  `Flint` options that are passed to `embeds_many` are stripped by `Flint` before passing them to `Ecto.Schema.embeds_many` and
  stored in module attributed for the schema's module.

  The following default options are passed to `Flint.Schema.embeds_many` and can be overriden at the `Application` level or at the
  local call level.

  ## Default Options

  ```elixir
  on_replace: :delete
  ```
  """
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

  @doc """
  Marks an embeds_many field as required by storing metadata in a module attribute, then calls `Flint.Schema.embeds_many`.

  The metadata tracking is not enforced at the schema / struct level (eg. through enforced keys), but rather
  at the schema validation level (through something such as `Flint.Pipeline.changeset`).

  The following default options are passed to `Flint.Schema.embeds_many!` and can be overriden at the `Application` level or at the
  local call level.

  ## Default Options

  ```elixir
  on_replace: :delete
  ```
  """
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

  @doc false
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

  @doc """
  Wraps `Ecto`'s `embedded_schema` macro, injecting `Flint`'s custom macro implementation into the module space.
  """
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

  @doc """
  Creates a new schema struct according to the schema's `changeset` implementation, immediately applying
  the changes from the changeset regardless of errors.

  If you want to manually handle error cases, you should use the `changeset` function itself.
  """
  def new(module, params \\ %{}, bindings \\ []) do
    apply(module, :changeset, [struct!(module), params, bindings])
    |> apply_changes()
  end

  @doc """
  Same as `new`, except will `raise` if any errors exist in the changeset.
  """
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
end
