defmodule Flint.Partial do
  @moduledoc """
  `Flint.Partial` is meant to make writing new `Ecto` types require much less boilerplate, because you can base your
  type off of an existing type and only modify the callbacks that have different behavior.

  Simply `use Flint.Partial` and pass the `:extends` option which says which type module to inherit callbacks
  from.  This will delegate all required callbacks and any implemented optional callbacks and make them
  overridable.

  It also lets you make a type from an `Ecto.ParameterizedType` with default parameter values.
  You may supply any number of default parameters. This essentially provides a new
  `init/1` implementation for the type, supplying the default values, while not affecting any of the
  other `Ecto.ParameterizedType` callbacks. You may still override the newly set defaults at the local level.

  Just supply all options that you wish to be defaults as extra options when using `Flint.Partial`.

  You may override any of the inherited callbacks inherity from the extended module
  in the case that you wish to customize the module further.

  ## Examples

  ``` elixir
  defmodule Category do
    use Flint.Partial, extends: Ecto.Enum, values: [:folder, :file]
  end
  ```

  This will apply default `values` to `Ecto.Enum` when you supply a `Category` type
  to an Ecto schema. You may still override the values if you supply the `:values`
  option for the field.
  """
  require Logger

  defmacro __using__(opts) do
    {extends, opts} = Keyword.pop!(opts, :extends)
    extends = Macro.expand_literals(extends, __CALLER__)

    unless Code.ensure_loaded?(extends) do
      raise ArgumentError, "Cannot load module #{inspect(extends)}!"
    end

    type =
      cond do
        implements_behaviour?(extends, Ecto.Type) ->
          Ecto.Type

        implements_behaviour?(extends, Ecto.ParameterizedType) ->
          Ecto.ParameterizedType

        true ->
          raise ArgumentError,
                "You must extend from either a `Ecto.Type` or `Ecto.ParameterizedType`!"
      end

    if type == Ecto.Type && opts != [] do
      Logger.warning("""
      You are passing options #{inspect(opts)} to `Flint.Partial`
      when extending a module of type `Ecto.Type`. `Ecto.Type` does not accept paremters, so these options will be ignored.
      """)
    end

    callbacks =
      type
      |> required_callbacks()
      |> Keyword.drop([:init])
      |> Enum.map(fn {name, arity} ->
        args = Macro.generate_arguments(arity, nil)

        quote do
          defdelegate unquote(name)(unquote_splicing(args)), to: unquote(extends)
          defoverridable [{unquote(name), unquote(arity)}]
        end
      end)

    callbacks =
      callbacks ++
        Enum.map(apply(type, :behaviour_info, [:optional_callbacks]), fn {name, arity} ->
          if function_exported?(extends, name, arity) do
            args = Macro.generate_arguments(arity, nil)

            quote do
              defdelegate unquote(name)(unquote_splicing(args)), to: unquote(extends)
              defoverridable [{unquote(name), unquote(arity)}]
            end
          end
        end)

    using = quote(do: use(unquote(type)))

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
  A shorthand for creating a new module to represent a partial `Ecto.ParameterizedType`. This is equivalent to
  creating a new module with name `module` and calling `use Flint.Partial` and passing `opts`.

  Practially speaking, this is only really useful for defining default values for an `Ecto.ParameterizedType` with
  no changes to any of the other callbacks.

  ## Example

  ```elixir
  defpartial Vehicle, extends: Ecto.Enum, values: [:car, :motorcycle, :truck]
  ```
  """
  def defpartial(module, opts) do
    quoted =
      quote do
        require Flint.Partial
        Flint.Partial.__using__(unquote(opts))
      end

    Module.create(module, quoted, Macro.Env.location(__ENV__))
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
end
