defmodule Flint.Partial do
  @moduledoc """
  Can be `use`d to create an `Ecto.ParameterizedType` based on another `Ecto.ParameterizedType`,
  applying default parameters. You may supply any number of default parameters. This essentially provides a new
  `init/1` implementation for the type, supplying the default values, while not affecting any of the
  other `Ecto.ParameterizedType` callbacks.

  You may still override the newly set defaults at the local level.

  You may override any of the inherited `Ecto.ParameterizedType` callbacks inherity from the extended module
  in the case that you wish to customize the module further.

  ## Examples

  ``` elixir
  defmodule Category do
    use Flint.Partial, extends: Ecto.Enum, values: [:folder, :file]
  end
  ```

  This will apply default `values` to `Ecto.Enum` when you supply a `Cateogory` type
  to an Ecto schema. You may still override the values if you supply the `:values`
  option for the field.
  """
  defmacro __using__(opts) do
    {extends, opts} = Keyword.pop!(opts, :extends)
    extends = Macro.expand_literals(extends, __CALLER__)

    unless Code.ensure_loaded?(extends) do
      raise ArgumentError, "Cannot load module #{inspect(extends)}!"
    end

    callbacks =
      Enum.map(
        [
          {:autogenerate, 1},
          {:embed_as, 2},
          {:format, 1},
          {:type, 1},
          {:cast, 2},
          {:load, 3},
          {:dump, 3},
          {:equal?, 3}
        ],
        fn {name, arity} ->
          if function_exported?(extends, name, arity) do
            args = Macro.generate_arguments(arity, nil)

            quote do
              defdelegate unquote(name)(unquote_splicing(args)), to: unquote(extends)
              defoverridable [{unquote(name), unquote(arity)}]
            end
          end
        end
      )
      |> Enum.filter(& &1)

    quote do
      use Ecto.ParameterizedType

      def init(opts) do
        opts = opts ++ unquote(opts)
        unquote(extends).init(opts)
      end

      unquote_splicing(callbacks)
    end
  end

  @doc """
  A shorthand for creating a new module to represent a partial `Ecto.ParameterizedType`. This is equivalent to
  creating a new module with name `module` and calling `use Flint.Partial` and passing `opts`.

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
end
