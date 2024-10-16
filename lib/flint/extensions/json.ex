defmodule Flint.Extensions.JSON do
  @moduledoc """
  Provides JSON encoding capabilities for Flint schemas with Go-like marshalling options.

  This extension enhances Flint schemas with customizable JSON serialization options,
  allowing fine-grained control over how fields are represented in JSON output.

  ## Usage

  To use this extension, include it in your Flint schema:

  ```elixir
  defmodule MySchema do
    use Flint.Schema,
       extensions: [{JSON, json_module: :json}]  # Jason, or Poison
       #extensions: [JSON] # (defaults to Jason if no args passed)

    embedded_schema do
      # Schema fields...
    end
  end
  ```

  ## JSON Encoding Options

  The following options can be specified for each field in your schema:

  - `:name` - Specifies a custom name for the field in the JSON output.
  - `:omitempty` - When set to `true`, omits the field from JSON output if its value is `nil`.
  - `:ignore` - When set to `true`, always excludes the field from JSON output.

  ## Defining Options

  Options are defined directly in your schema using the `field` macro:

  ```elixir
  embedded_schema do
    field :id, :string, name: "ID"
    field :title, :string, name: "Title", omitempty: true
    field :internal_data, :map, ignore: true
  end
  ```

  ## Example

  ```elixir
  defmodule Book do
    use Flint.Schema,
      extensions: [Embedded, Accessible, JSON]

    embedded_schema do
      field :id, :string, name: "ISBN"
      field :title, :string
      field :author, :string, omitempty: true
      field :price, :decimal, name: "SalePrice"
      field :internal_notes, :string, ignore: true
    end
  end

  book = %Book{
    id: "978-3-16-148410-0",
    title: "Example Book",
    author: nil,
    price: Decimal.new("29.99"),
    internal_notes: "Not for customer eyes"
  }

  Jason.encode!(book)
  # Results in:
  # {
  #   "ISBN": "978-3-16-148410-0",
  #   "title": "Example Book",
  #   "SalePrice": "29.99"
  # }
  ```

  Note how the `author` field is omitted due to `omitempty: true`, the `internal_notes`
  field is ignored, and custom names are used for `id` and `price`.

  ## Introspection

  You can inspect the JSON options for a schema using the `__schema__/1` function:

  ```elixir
  Book.__schema__(:extra_options)
  # Returns:
  # [
  #   id: [name: "ISBN"],
  #   title: [],
  #   author: [omitempty: true],
  #   price: [name: "SalePrice"],
  #   internal_notes: [ignore: true]
  # ]
  ```

  This allows for runtime inspection and manipulation of JSON encoding behavior.

  ## Implementation Details

  This extension implements the `Jason.Encoder` protocol for your schema, automatically
  applying the specified options during JSON encoding. It leverages Flint's schema
  introspection capabilities to retrieve and apply the options.

  The encoding process:
  1. Converts the struct to a map
  2. Applies the `:name` option to change key names
  3. Applies the `:omitempty` option to remove nil values
  4. Applies the `:ignore` option to exclude specified fields
  5. Encodes the resulting map to JSON

  This approach provides a flexible and powerful way to control JSON serialization
  directly from your schema definition, promoting clean and maintainable code.
  """
  use Flint.Extension

  option :name, required: false, validator: &is_binary/1
  option :omitempty, required: false, default: false, validator: &is_boolean/1
  option :ignore, required: false, default: false, validator: &is_boolean/1

  @doc false
  def encode_to_map(module, struct) do
    struct
    |> Ecto.embedded_dump(:json)
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      field_opts = get_field_options(module, key)
      json_key = field_opts[:name] || to_string(key)

      cond do
        field_opts[:ignore] ->
          acc

        field_opts[:omitempty] && is_nil(val) ->
          acc

        true ->
          Map.put(acc, json_key, val)
      end
    end)
  end

  defp get_field_options(module, field) do
    module.__schema__(:extra_options)
    |> Keyword.get(field, [])
    |> Enum.into(%{})
  end

  defmacro __using__(opts) do
    json_module = Keyword.get(opts, :json_module, Jason)
    protocol = Module.concat([json_module, Encoder])

    quote do
      if Code.ensure_loaded?(unquote(json_module)) do
        defimpl unquote(protocol) do
          def encode(value, opts) do
            encoded_map = Flint.Extensions.JSON.encode_to_map(unquote(__CALLER__.module), value)
            unquote(Module.concat([json_module, Encoder, Map])).encode(encoded_map, opts)
          end
        end
      end
    end
  end
end
