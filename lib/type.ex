defmodule Flint.Type do
  @moduledoc """
  `Flint.Type` is meant to make writing new `Ecto` types require much less boilerplate, because you can base your
  type off of an existing type and only modify the callbacks that have different behavior.

  Simply `use Flint.Type` and pass the `:extends` option which says which type module to inherit callbacks
  from.  This will delegate all required callbacks and any implemented optional callbacks and make them
  overridable.

  It also lets you make a type from an `Ecto.ParameterizedType` with default parameter values.
  You may supply any number of default parameters. This essentially provides a new
  `init/1` implementation for the type, supplying the default values, while not affecting any of the
  other `Ecto.ParameterizedType` callbacks. You may still override the newly set defaults at the local level.

  Just supply all options that you wish to be defaults as extra options when using `Flint.Type`.

  You may override any of the inherited callbacks inherity from the extended module
  in the case that you wish to customize the module further.

  ## Examples

  ``` elixir
  defmodule Category do
    use Flint.Type, extends: Ecto.Enum, values: [:folder, :file]
  end
  ```

  This will apply default `values` to `Ecto.Enum` when you supply a `Category` type
  to an Ecto schema. You may still override the values if you supply the `:values`
  option for the field.

  ```elixir
  import Flint.Type
  deftype NewUID, extends: Ecto.UUID, dump: &String.length/1
  ```

  This will create a new `NewUID` type that behaves exactly like an `Ecto.UUID` except it dumps
  its string length.
  """
  require Logger

  defmacro __using__(opts) do
    {extends, opts} = Keyword.pop!(opts, :extends)

    extends = Macro.expand_literals(extends, __CALLER__)

    unless Ecto.Type.base?(extends) || Ecto.Type.composite?(extends) ||
             Code.ensure_loaded?(extends) do
      raise ArgumentError, "Cannot load module #{inspect(extends)}!"
    end

    type =
      cond do
        Ecto.Type.base?(extends) ->
          extends

        Ecto.Type.composite?(extends) ->
          extends

        implements_behaviour?(extends, Ecto.Type) ->
          Ecto.Type

        implements_behaviour?(extends, Ecto.ParameterizedType) ->
          Ecto.ParameterizedType

        true ->
          raise ArgumentError,
                "You must extend from either a base type, a composite type, an `Ecto.Type`, or an `Ecto.ParameterizedType`!"
      end

    {impls, opts} =
      Keyword.split(
        opts,
        Keyword.keys(apply(module_for_type(type), :behaviour_info, [:callbacks]))
      )

    if type != Ecto.ParameterizedType && opts != [] do
      Logger.warning("""
      You are passing options #{inspect(opts)} to type `#{inspect(extends)}`
      `#{inspect(extends)}` does not accept paremters, so these options will be ignored.

      Only `Ecto.ParameterizedType` accepts parameters.
      """)
    end

    required =
      required_callbacks(module_for_type(type))

    callbacks =
      module_for_type(type)
      |> apply(:behaviour_info, [:callbacks])
      |> Keyword.drop([:init])
      |> Enum.map(fn {name, arity} ->
        cond do
          Keyword.has_key?(impls, name) ->
            args = Macro.generate_arguments(arity, nil)

            option =
              Keyword.fetch!(impls, name)

            quote do
              if is_function(unquote(option), unquote(arity)) do
                def unquote(name)(unquote_splicing(args)),
                  do: unquote(option).(unquote_splicing(args))
              else
                raise ArgumentError,
                      "Function and arity mismatch for callback #{Exception.format_mfa(unquote(type), unquote(name), unquote(arity))} in module #{inspect(__MODULE__)}."
              end
            end

          Keyword.has_key?(required, name) ||
              function_exported?(extends, name, arity) ->
            args = Macro.generate_arguments(arity, nil)

            if type in [Ecto.Type, Ecto.ParameterizedType] do
              quote do
                def unquote(name)(unquote_splicing(args)) do
                  unquote(extends).unquote(name)(unquote_splicing(args))
                end

                defoverridable [{unquote(name), unquote(arity)}]
              end
            else
              quote do
                def unquote(name)(unquote_splicing(args)) do
                  Ecto.Type.unquote(name)(unquote(extends), unquote_splicing(args))
                end

                defoverridable [{unquote(name), unquote(arity)}]
              end
            end

          true ->
            nil
        end
      end)

    using = quote(do: use(unquote(module_for_type(type))))

    init =
      if type == Ecto.ParameterizedType do
        quote do
          def init(opts) do
            opts = opts ++ unquote(opts)
            unquote(extends).init(opts)
          end
        end
      end

    quoted =
      ([
         using,
         init
       ] ++
         callbacks)
      |> Enum.filter(& &1)

    quote do
      (unquote_splicing(quoted))
    end
  end

  @doc """
  A shorthand for creating a new `Flint.Type`. This is equivalent to
  creating a new module with name `module` and calling `use Flint.Type` and passing `opts`.

  ## Example

  ```elixir
  deftype Vehicle, extends: Ecto.Enum, values: [:car, :motorcycle, :truck]
  ```
  """
  defmacro deftype(module, opts) do
    module = Macro.expand_literals(module, __CALLER__)

    quote do
      defmodule unquote(module) do
        use Flint.Type, unquote(opts)
      end
    end
  end

  defp required_callbacks(module) do
    all_callbacks = apply(module, :behaviour_info, [:callbacks])
    optional_callbacks = apply(module, :behaviour_info, [:optional_callbacks])
    Keyword.drop(all_callbacks, Keyword.keys(optional_callbacks))
  end

  defp implements_behaviour?(module, behaviour) do
    Enum.all?(required_callbacks(behaviour), fn {k, v} ->
      function_exported?(module, k, v)
    end)
  end

  defp module_for_type(Ecto.ParameterizedType), do: Ecto.ParameterizedType

  defp module_for_type(_other), do: Ecto.Type
end
