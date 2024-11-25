if Code.ensure_loaded?(TypedEctoSchema) || Mix.env() == :docs do
  defmodule Flint.Extensions.Typed do
    @moduledoc """
     Adds supports for **most** of the features from the wonderful [`typed_ecto_schema`](https://github.com/bamorim/typed_ecto_schema) library.

    Rather than using the `typed_embedded_schema` macro from that library, however, thr `Typed` extension incorporates the features into the standard
    `embedded_schema` macro from `Flint.Schema`, meaning even fewer lines of code changed to use typed embedded schemas!

    Included with that are the addtional [Schema-Level options](https://hexdocs.pm/typed_ecto_schema/TypedEctoSchema.html#module-schema-options)
    you can pass to the `embedded_schema` macro.

    You also have the ability to [override field typespecs ](https://hexdocs.pm/typed_ecto_schema/TypedEctoSchema.html#module-overriding-the-typespec-for-a-field) as well as providing extra [field-level options](https://hexdocs.pm/typed_ecto_schema/TypedEctoSchema.html#module-extra-options) from
    `typed_ecto_schema`.

    > #### Required vs Enforced vs Null {: .info}
    > Note that the typespecs allow you to specify `:enforce` and `:null` options, which are different from the requirement imposed by `field!`.
    > ---
    > `field!` marks the field as being required during the
    > changeset validation, which is equal to passing
    > the field name to the [`Eco.Changeset.validate_required/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_required/3).
    > An instance of the schema's struct **CAN** still be created if a field marked with `field!` is not present.
    > ---
    > `enforce: true` is equal to including that field in the [`@enforce_keys` module attribute](https://hexdocs.pm/elixir/structs.html#default-values-and-required-keys)
    > for the corresponding schema struct.
    >
    > An instance of the schema's struct **CANNOT** be created if a field marked with `enforce: true` is not present, as it
    > will `raise` an `ArgumentError`.
    > ---
    >`:null` indicates whether `nil` is a valid value for the field. This **only** impacts the generated typespecs.
    """
    use Flint.Extension
    alias TypedEctoSchema.TypeBuilder

    @schema_function_names [
      :field,
      :field!,
      :embeds_one,
      :embeds_one!,
      :embeds_many,
      :embeds_many!
    ]

    @embeds_function_names [:embeds_one, :embeds_many, :embeds_many!, :embeds_one!]

    defmacro embedded_schema(opts \\ [], do: block) do
      {mod, _macros} = Flint.Extension.__context__(__CALLER__, __MODULE__)

      quote do
        unquote(mod).embedded_schema do
          require unquote(TypeBuilder)

          unquote(TypeBuilder).init(unquote(opts))

          unquote(TypeBuilder).add_primary_key(__MODULE__)
          unquote(apply_to_block(block, __CALLER__))
          unquote(TypeBuilder).enforce_keys()
          unquote(TypeBuilder).define_type(unquote(opts))
        end
      end
    end

    defp filter_options(opts, module) do
      Module.get_attribute(module, :extension_options, [])
      |> Enum.map(& &1.name)
      |> Enum.concat([:do | Flint.Schema.aliases() |> Enum.map(&elem(&1, 0))])
      |> then(fn filtered -> Keyword.drop(opts, filtered) end)
    end

    defp apply_to_block(block, env) do
      calls =
        case block do
          {:__block__, _, calls} ->
            calls

          call ->
            [call]
        end

      new_calls = Enum.map(calls, &transform_expression(&1, env))

      {:__block__, [], new_calls}
    end

    defp transform_expression({function_name, ctx, [name, schema, [do: block]]}, env)
         when function_name in @embeds_function_names do
      transform_expression({function_name, ctx, [name, schema, [], [do: block]]}, env)
    end

    defp transform_expression({function_name, _, [name, type, opts]}, env)
         when function_name in @schema_function_names do
      ecto_opts = Keyword.drop(opts, [:__typed_ecto_type__, :enforce, :null])

      quote do
        unquote(function_name)(unquote(name), unquote(type), unquote(ecto_opts))

        unquote(TypeBuilder).add_field(
          __MODULE__,
          unquote(function_name),
          unquote(name),
          unquote(Macro.escape(type)),
          unquote(filter_options(opts, env.module))
        )
      end
    end

    defp transform_expression({function_name, _, [name, type]}, _env)
         when function_name in @schema_function_names do
      quote do
        unquote(function_name)(unquote(name), unquote(type))

        unquote(TypeBuilder).add_field(
          __MODULE__,
          unquote(function_name),
          unquote(name),
          unquote(Macro.escape(type)),
          []
        )
      end
    end

    defp transform_expression({field, _, [name]}, _env) when field in [:field, :field!] do
      quote do
        unquote(field)(unquote(name))

        unquote(TypeBuilder).add_field(
          __MODULE__,
          :field,
          unquote(name),
          :string,
          []
        )
      end
    end

    defp transform_expression({function_name, _, [name, schema, opts, [do: block]]}, env)
         when function_name in @embeds_function_names do
      schema = Flint.Schema.expand_nested_module_alias(schema, env)

      normalized_function_name =
        case function_name do
          :embeds_many! ->
            :embeds_many

          :embeds_one! ->
            :embeds_one

          other ->
            other
        end

      quote do
        {schema, opts} =
          Flint.Schema.__embeds_module__(
            __ENV__,
            unquote(schema),
            unquote(opts),
            unquote(Macro.escape(block))
          )

        unquote(function_name)(unquote(name), schema, opts)

        unquote(TypeBuilder).add_field(
          __MODULE__,
          unquote(normalized_function_name),
          unquote(name),
          schema,
          unquote(opts)
        )
      end
    end

    defp transform_expression(
           {:"::", _, [{function_name, _, [name, ecto_type, opts]}, type]},
           env
         )
         when function_name in @schema_function_names do
      transform_expression(
        {function_name, [],
         [name, ecto_type, [{:__typed_ecto_type__, Macro.escape(type)} | opts]]},
        env
      )
    end

    defp transform_expression({:"::", _, [{function_name, _, [name, ecto_type]}, type]}, env)
         when function_name in @schema_function_names do
      transform_expression(
        {function_name, [], [name, ecto_type, [__typed_ecto_type__: Macro.escape(type)]]},
        env
      )
    end

    defp transform_expression({:"::", _, [{field, _, [name]}, type]}, env)
         when field in [:field, :field!] do
      transform_expression(
        {field, [], [name, :string, [__typed_ecto_type__: Macro.escape(type)]]},
        env
      )
    end

    defp transform_expression(unknown, env) do
      expanded = Macro.expand(unknown, env)

      case expanded do
        {:__block__, block_context, calls} ->
          new_calls = Enum.map(calls, &transform_expression(&1, env))
          {:__block__, block_context, new_calls}

        ^unknown ->
          unknown

        call ->
          transform_expression(call, env)
      end
    end

    defmacro __using__(_opts) do
      {mod, macros} = Flint.Extension.__embedded_schema__(__CALLER__, __MODULE__)

      quote do
        import unquote(mod), except: unquote(macros)
        import unquote(__MODULE__), only: [embedded_schema: 1, embedded_schema: 2]
      end
    end
  end
end
