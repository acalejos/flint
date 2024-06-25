# Flint

[![Flint version](https://img.shields.io/hexpm/v/flint.svg)](https://hex.pm/packages/flint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/flint/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/flint)](https://hex.pm/packages/flint)
[![Twitter Follow](https://img.shields.io/twitter/follow/ac_alejos?style=social)](https://twitter.com/ac_alejos)
<!-- BEGIN MODULEDOC -->

Practical [`Ecto`](https://github.com/elixir-ecto/ecto) `embedded_schema`s for data validation, coercion, and manipulation.

Flint is built on top of Ecto and is meant to provide good defaults for using `embedded_schema`s for use outside of a database.

Of course, since you're using Ecto, you can use this for use as an ORM, but this is emphasizing the use of `embedded_schema`s as just more expressive and powerful maps while keeping compatibility with `Ecto.Changeset`, `Ecto.Type`, and all of the other benefits Ecto has to offer.

In particular, `Flint` focuses on making it more ergonomic to use `embedded_schema`s as a superset of Maps, so a `Flint.Schema` by default implements the `Access` behaviour and implements the `Jason.Encoder` protocol.

`Flint` also was made to leverage the distinction `Ecto` makes between the embedded representation of the schema and the dumped representation. This means that you can dictate how you want the Elixir-side representation to look, and then provide transformations
for how it should be dumped, which helps when you want the serialized representation to look different.

This is useful if you want to make changes in the server-side code without needing to change the client-side (or vice-versa). Or perhaps you want a mapped representation, where instead of an `Ecto.Enum` just converting its atom key to a string when dumped, it gets mapped to an integer, etc.

## Usage

If you want to declare a schema with `Flint`, just `use Flint` within your module and pass your `:schema` as the last keyword argument.

You can also provide the following options which will be passed as module attributes to the `Ecto` `embedded_schema`. Refer to the [`Ecto.Schema`](https://hexdocs.pm/ecto/Ecto.Schema.html#module-schema-attributes) docs for more about these options.

* `primary_key` (default `false`)
* `schema_prefix` (default `nil`)
* `schema_context` (default `nil`)
* `timestamp_opts` (default `[type: :naive_datetime]`)

Since a call to `use Flint` just creates an `Ecto` `embedded_schema` you can use them just as you would any other `Ecto` schemas. You can compose them, apply changesets to them, etc.

```elixir
defmodule User do
  use Flint, schema: [
    field!(:username, :string)
    field!(:password, :string, redacted: true)
    field(:nickname, :string)
  ]
end
```

## API Additions

`Flint` adds the convenience bang (`!`) macros (`embed_one!`,`embed_many!`, `field!`) for field declarations within your struct to declare a field as required within its `changeset` function.

`Flint` provides default implementations for the following functions for any schema declaration:

* `changeset` - Creates a changeset by casting all fields and validating all that were marked as required. If a `:default` key is provided for a field, then any use of a bang (`!`) declaration will essentially be ignored since the cast will fall back to the default before any valdiations are performed.
* `new` - Creates a new changeset from the empty module struct and applies the changes (regardless of whether the changeset was valid).
* `new!` - Same as new, except raises if the changeset is not valid.

`Flint` schemas also have a new reflection function in addition to the normal [`Ecto` reflection functions](https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection).

* `__schema__(:required)` -- Returns a list of all fields that were marked as required.

## Config

You can configure the default options set by `Flint`.

* `embeds_one`: The default arguments when using `embeds_one`. Defaults to `[defaults_to_struct: true, on_replace: :delete]`
* `embeds_one!`: The default arguments when using `embeds_one!`. Defaults to `[on_replace: :delete]`
* `embeds_many`: The default arguments when using `embeds_many` or `embeds_many!`. Defaults to `[on_replace: :delete]`
* `embeds_many!`: The default arguments when using `embeds_many!`. Defaults to `[on_replace: :delete]`

* `:enum`: The default arguments for an `Ecto.Enum` field. Defaults to `[embed_as: :dumped]`.

## Embedded vs Dumped Representations

`Flint` takes advantage of the distinction `Ecto` makes between an `embedded_schema`'s embedded and dumped representations.

For example, by default in `Flint`, `Ecto.Enum`s that are `Keyword` (rather than just lists of atoms) will have their keys
be the embedded representation, and will have the values be the dumped representation.

```elixir
defmodule Book do
  use Flint, schema: [
    field(:genre, Ecto.Enum, values: [biography: 0, science_fiction: 1, fantasy: 2, mystery: 3])
  ]
end

book = Book.new(%{genre: "biography"})
# %Book{genre: :biography}

Flint.Schema.dump(book)
# %{genre: 0}
```

In this example, you can see how you can share multiple representations of the same data using this distinction.

You can also implement your own `Ecto.Type` and further customize this:

```elixir
defmodule ContentType do
  use Ecto.Type
  def type, do: :atom

  def cast("application/json"), do: {:ok, :json}

  def cast(_), do: :error
  def load(_), do: :error

  def dump(:json), do: {:ok, "application/json"}
  def dump(_), do: :error

  def embed_as(_) do
    :dump
  end
end
```

Here, `cast` will be called when creating a new `Flint` schema from a map, and `dump` will be used
when calling `Flint.Schema.dump/1`.

```elixir
defmodule URL do
  use Flint, schema: [
    field(:content_type, ContentType)
  ]
end
```

```elixir
url = URL.new(%{content_type: "application/json"})
# %URL{content_type: :json}

Flint.Schema.dump(url)
# %{content_type: "application/json"}
```

## Examples

You can view the [Notebooks folder](https://github.com/acalejos/flint/tree/main/notebooks) for some examples in LIivebook.

You can also look at [Merquery](https://github.com/acalejos/merquery/tree/main/lib/merquery/schemas) for a real, comprehensive
example of how to use `Flint`.

## Installation

```elixir
def deps do
  [
    {:flint, github: "acalejos/flint"}
  ]
end
```

<!-- END MODULEDOC -->