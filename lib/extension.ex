defmodule Flint.Extension do
  @moduledoc """
  `Flint` extensions allow developers to easily hook into `Flint` metaprogramming lifecycle to add extra data into the embedded
  schema reflection functions.

  Flint currently offers four ways to extend behavior:

  1. Schema-level attributes
  2. Field-level additional options
  3. Default `embedded_schema` definitions
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

  ## Default `embedded_schema` definitions

  Sometimes you might want to always have one of more fields defined for a given schema type without having
  to write it each time. Much in the same way that, by default, the `@prmimary_key` attribute will set an `:id` field
  for the schema, you might wish to template out some fields and values.

  If you want to define fields that are defined by default in a schema that uses your extension, you can use the
  `embedded_schema` macro within an extension and all `field`, `embeds_one` and `embeds_many` declarations will be
  merged into the target schema that uses your extension.

  These accept the same arguments as their counterparts in `Flint.Schema`, and will be
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

    embedded_schema do
      field! :timestamp, :utc_datetime_usec
      field! :id, :binary_id
    end
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

  *  `Flint.Extensions.Block`
  *  `Flint.Extensions.Typed`
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

  @callback changeset(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  @callback changeset(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()

  def eval_quoted(quoted, binding \\ [], env_or_opts \\ []) do
    {:ok, capture_pid} = StringIO.open("")
    original_group_leader = Process.group_leader()

    try do
      Process.group_leader(self(), capture_pid)

      {:ok,
       Code.eval_quoted(
         quoted,
         binding,
         env_or_opts
       )}
    rescue
      _ ->
        :error
    after
      Process.group_leader(self(), original_group_leader)
    end
  end

  @doc false
  defmacro embedded_schema(do: {:__block__, _, contents}) do
    Module.put_attribute(__CALLER__.module, :embedded_schema, contents)
  end

  @doc false
  defmacro embedded_schema(do: block) do
    Module.put_attribute(__CALLER__.module, :embedded_schema, [block])
  end

  @doc false
  def __embedded_schema__(env, extension) do
    mods =
      env.macros
      |> Enum.find_value(
        fn {_mod, exports} -> Keyword.has_key?(exports, :embedded_schema) end,
        fn {mod, exports} ->
          {mod, Keyword.take(exports, [:embedded_schema])}
        end
      )

    Module.put_attribute(env.module, :__embedded_schema_super__, {extension, mods})

    mods
  end

  @doc false
  def __context__(env, extension) do
    Module.get_attribute(env.module, :__embedded_schema_super__)
    |> Keyword.fetch!(extension)
  end

  defmacro __using__(opts) do
    Module.put_attribute(__CALLER__.module, :embedded_schema, [])

    quote do
      import Flint.Extension
      @behaviour Flint.Extension
      unquote_splicing(super(opts))

      @impl true
      def changeset(changeset, bindings \\ []) do
        changeset
      end

      defmacro __using__(opts) do
        quote do
        end
      end

      defoverridable __using__: 1
      defoverridable Flint.Extension

      @doc false
      def template_schema() do
        @embedded_schema
      end

      @doc false
      def option_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :options) |> Enum.map(& &1.name)

      @doc false
      def attribute_names(),
        do: Spark.Dsl.Extension.get_entities(__MODULE__, :attributes) |> Enum.map(& &1.name)
    end
  end
end
