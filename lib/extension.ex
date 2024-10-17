defmodule Flint.Extension do
  @moduledoc """
  `Flint` extensions allow developers to easily hook into `Flint` metaprogramming lifecycle to add extra data into the embedded
  schema reflection functions.

  Flint currently offers three ways to extend behavior:

  1. Schema-level attributes
  2. Field-level additional options
  3. Injected Code

  Extension authors define what fields / options / attributes `Flint` should look for in the module / schema definition and
  strip out and store in a schema reflection function, but it is still the resposibility of either the extension author or
  the end user to make use of the stored information.

  ## Schema-Level Attributes

  These are simply module attributes that are pre-registered with `Flint`, and can be given a default value
  as well as a validation function. When you use an extension that registers an attribute, then a new `__schema__`
  reflection function is added for each attribute name, with the attribute name as the argument.

  **Note that the validation occurs at compile time**

  ### Example

  Given the following extension:

  ```elixir
  defmodule Returnable do
    use Flint.Extension

    attribute :returns, validator: fn returns -> is_binary(returns) end
  end
  ```

  And the schema

  ```elixir
  defmodule Schema do
    use Flint.Schema, extensions: [Returnable]
    @returns "something"
    embedded_schema do
      ...
    end
  end
  ```

  Then you can reflect on this new attribute with:

  ```elixir
  Schema.__schema__(:returns)
  ```

  ## Field-Level Options

  You can also register additional field-level keyword options to be consumed in a downstream function.

  These function similarly to the built-in extra options that `Flint` provides, where the options are
  stripped and stored in a module attribute (and subsequently in a `__schema__` reflection function)
  before passing the valid `Ecto.Schema` options to `Ecto` itself.

  **Note that the validation occurs at compile time**

  ### Example

  Given the following extension that enables Go-like JSON marshalling options:

  ```elixir
  defmodule JSON do
    use Flint.Extension

    option :name, required: false, validator: &is_binary/1
    option :omitempty, required: false, default: false, validator: &is_boolean/1
    option :ignore, required: false, default: false, validator: &is_boolean/1
  end
  ```

  And the following schema:

  ```elixir
  defmodule Schema do
    use Flint.Schema, extensions: [JSON]
    embedded_schema do
      field :myfield, :string, name: "my_field", omitempty: true
    end
  end
  ```

  Then you can access these specific fields with:

  ```elixir
  Schema.__schema__(:extra_options)
  ```

  ```elixir
  [
    myfield: [ignore: false, omitempty: true, name: "my_field"],
  ]
  ```

  ## Injected Code

  Lastly, extensions allow you to define custom `__using__/1` macros which will be passed through
  to the target schema module. This is one of the core functionalities of extensions, and works the
  same as you would normally `use` a module, and helps compartmentalize similar functionality.

  ## Default Extensions

  By default, `Flint` will enable the following extensions:

  * `JSON`
  * `Accessible`
  * `Embedded`

  If you want to pass your own list of extensions for a module, you will need to explicitly pass the defaults
  as well if you would like to keep them. You can use the convenience `Flint.default_extensions/0` constant
  if you want to include all of the defaults.
  """
  use Spark.Dsl,
    many_extension_kinds: [:extensions],
    default_extensions: [extensions: Flint.Extension.Dsl]

  defmacro __using__(opts) do
    quote do
      unquote_splicing(super(opts))

      defmacro __using__(opts) do
        quote do
        end
      end

      defoverridable __using__: 1

      def option_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :options) |> Enum.map(& &1.name)

      def attribute_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :attributes) |> Enum.map(& &1.name)
    end
  end
end
