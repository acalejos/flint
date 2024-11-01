defmodule Flint.Extension do
  @moduledoc """
  `Flint` extensions allow developers to easily hook into `Flint` metaprogramming lifecycle to add extra data into the embedded
  schema reflection functions.

  Flint currently offers three ways to extend behavior:

  1. Schema-level attributes
  2. Field-level additional options
  3. Default `field` and `field!` definitions
  4. Injected Code

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

  ## Default `field` and `field!` definitions

  Sometimes you might want to always have one of more fields defined for a given schema type without having
  to write it each time. Much in the same way that, by default, the `@prmimary_key` attribute will set an `:id` field
  for the schema, you might wish to template out some fields and values.

  If you want to define fields that are defined by default in a schema that uses your extension, just use the
  `field` and `field!` macros. These accept the same arguments as their counterparts in `Flint.Schema`, and will be
  added at the end of the `embedded_schema` definition.

  > #### Duplicate Fields {: .info}
  >
  > Note that if you define a template for a field in your extension then anyone who uses your extension will be
  > unable to override that field name with their own definition.

  ### Example

  Given the following extension:

  ```elixir
  defmodule Event do
    use Flint.Extension

    field! :timestamp, :utc_datetime_usec
    field! :id, :binary_id
  end
  ```

  and this schema:

  ```elixir
  defmodule Webhook do
    use Flint.Schema, extensions: [Event, Embedded]

    embedded_schema do
      field :route, :string
    end
  end
  ```

  Then any schema that uses this extension will have these fields by default:

  ```elixir
  Webhook.__schema__(:fields)
  # [:route, :timestamp, :id]
  ```

  ## Injected Code

  Lastly, extensions allow you to define custom `__using__/1` macros which will be passed through
  to the target schema module. This is one of the core functionalities of extensions, and works the
  same as you would normally `use` a module, and helps compartmentalize similar functionality.

  ## Default Extensions

  By default, `Flint` will enable the following extensions:

  *  `Flint.Extensions.PreTransforms`,
  *  `Flint.Extensions.When`,
  *  `Flint.Extensions.EctoValidations`,
  *  `Flint.Extensions.PostTransforms`,
  *  `Flint.Extensions.Accessible`,
  *  `Flint.Extensions.Embedded`,
  *  `Flint.Extensions.JSON`

  If you want to pass your own list of extensions for a module, you will need to explicitly pass the defaults
  as well if you would like to keep them. You can use the convenience `Flint.default_extensions/0` constant
  if you want to include all of the defaults.
  """
  use Spark.Dsl,
    many_extension_kinds: [:extensions],
    default_extensions: [extensions: Flint.Extension.Dsl]

  @doc """
  Registers a default field to be added to any `embedded_schema` using this extension
  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      entity do
        name(unquote(name))
        type(unquote(type))
        opts(unquote(opts))
      end
    end
  end

  @doc """
  Same as `field` but marks the field as required
  """
  defmacro field!(name, type \\ :string, opts \\ []) do
    quote do
      entity do
        name(unquote(name))
        type(unquote(type))
        opts(unquote(opts))
        required(true)
      end
    end
  end

  defmacro __using__(opts) do
    quote do
      import Flint.Extension
      unquote_splicing(super(opts))

      defmacro __using__(opts) do
        quote do
        end
      end

      defoverridable __using__: 1

      @doc false
      def option_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :options) |> Enum.map(& &1.name)

      @doc false
      def attribute_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :attributes) |> Enum.map(& &1.name)

      def field_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :fields) |> Enum.map(& &1.name)
    end
  end
end
