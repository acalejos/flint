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

## Installation

```elixir
def deps do
  [
    {:flint, github: "acalejos/flint"}
  ]
end
```

## Usage

If you want to declare a schema with `Flint`, just `use Flint` within your module, and now you have access to `Flint`'s implementation of the
`embedded_schema/1` macro.  You can declare an `embedded_schema` within your module as you otherwise would with `Ecto`. Within the `embedded_schema/1` block, you also have access to `Flint`s implementations of `embeds_one`,`embeds_one!`,`embeds_many`, `embeds_many!`, `field`, and `field!`.

You can also use the shorthand notation, where you pass in your schema definition as an argument to the `use/2` macro. `Flint.__using__/1` also
accepts the following options which will be passed as module attributes to the `Ecto` `embedded_schema`. Refer to the [`Ecto.Schema`](https://hexdocs.pm/ecto/Ecto.Schema.html#module-schema-attributes) docs for more about these options.

* `primary_key` (default `false`)
* `schema_prefix` (default `nil`)
* `schema_context` (default `nil`)
* `timestamp_opts` (default `[type: :naive_datetime]`)

So these two are equivalent:

```elixir
defmodule User do
  use Flint

  embedded_schema do
    field! :username, :string
    field! :password, :string, redacted: true
    field :nickname, :string
  end
end
```

is equivalent to:

```elixir
defmodule User do
  use Flint, schema: [
    field!(:username, :string)
    field!(:password, :string, redacted: true)
    field(:nickname, :string)
  ]
end
```

If you're starting with `Flint` and you know you will stick with it, the shorthand might make more sense. But if you want to be able to quickly
change between `use Ecto.Schem` and `use Flint`, or you're converting some existing `Ecto` `embedded_schema`s to `Flint`, the latter might be
preferable.

Since a call to `Flint`'s `embedded_schema` or `use Flint, schema: []`  just creates an `Ecto` `embedded_schema` you can use them just as you would any other `Ecto` schemas. You can compose them, apply changesets to them, etc.

## Required Fields

`Flint` adds the convenience bang (`!`) macros (`embed_one!`,`embed_many!`, `field!`) for field declarations within your struct to declare a field as required within its `changeset` function.

`Flint` schemas also have a new reflection function in addition to the normal [`Ecto` reflection functions](https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection).

* `__schema__(:required)` -- Returns a list of all fields that were marked as required.

## Field Validations

### Basic Validations

`Flint` allows you to colocate schema definitions and validations.

```elixir
defmodule Person do
  use Flint

  embedded_schema do
    field! :first_name, :string,  max: 10, min: 5
    field! :last_name, :string, min: 5, max: 10
    field :favorite_colors, {:array, :string}, subset_of: ["red", "blue", "green"]
    field! :age, :integer, greater_than: 0, less_than: 100
  end
end
```

### Parameterized Validations

You can even parameterize the options passed to the validations:

```elixir
defmodule Person do
  use Flint

  embedded_schema do
    field! :first_name, :string,  max: 10, min: 5
    field! :last_name, :string, min: 5, max: 10
    field :favorite_colors, {:array, :string}, subset_of: ["red", "blue", "green"]
    field! :age, :integer, greater_than: 0, less_than: max_age
  end
end
```

If you do this, make sure to pass the options as a keyword list into the call to `changeset`:

```elixir
Person.changeset(
  %Person{},
  %{first_name: "Bob", last_name: "Smith", favorite_colors: ["red", "blue", "pink"], age: 101},
  [max_age: 100]
)
```

```elixir
#Ecto.Changeset<
  action: nil,
  changes: %{
    age: 101,
    first_name: "Bob",
    last_name: "Smith",
    favorite_colors: ["red", "blue", "pink"]
  },
  errors: [
    first_name: {"should be at least %{count} character(s)",
     [count: 5, validation: :length, kind: :min, type: :string]},
    favorite_colors: {"has an invalid entry", [validation: :subset, enum: ["red", "blue", "green"]]},
    age: {"must be less than %{number}", [validation: :number, kind: :less_than, number: 100]}
  ],
  data: #Person<>,
  valid?: false,
  ...
>
```

This lets you change the parameters of the validations for each call to `changeset` for more flexibility

### Options

Currently, the options / validations supported out of the box with `Flint` are all based on validation functions
defined in `Ecto.Changeset`:

* `:greater_than` (see. [`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:less_than` (see. [`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:less_than_or_equal_to` (see. [`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:greater_than_or_equal_to` (see. [`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:equal_to` (see. [`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:not_equal_to` (see. [`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:format` (see. [`Ecto.Changeset.validate_format/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_format/4))
* `:subset_of` (see. [`Ecto.Changeset.validate_subset/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_subset/4))
* `:in` (see. [`Ecto.Changeset.validate_inlusion/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_inclusion/4))
* `:not_in` (see. [`Ecto.Changeset.validate_exclusion/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_exclusion/4))
* `:is` (see. [`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:min` (see. [`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:max` (see. [`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:count` (see. [`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))

### Aliases

If you don't like the name of an option, you can provide a compile-time list of aliases to map new option names to [existing options](#options).

In your config, add an `:aliases` key with a `Keyword` value, where each key is the new alias, and the value is an existing option name.

For example, these are default aliases implemented in `Flint`:

```elixir
config Flint, aliases: [
    lt: :less_than,
    gt: :greater_than,
    le: :less_than_or_equal_to,
    ge: :greater_than_or_equal_to,
    eq: :equal_to,
    neq: :not_equal_to
  ]
```

**NOTE** If you add your own aliases and want to keep these above defaults, you will have to add them manually to your aliases.

### `__schema__(:validations)`

Since validations are enforced through the generated `changeset` functions, if you override this function you will not get the benefits
of the validations.

If you want to implement your own, you can use `__schema__(:validations)` which is an added reflection function that stores validations.

**NOTE** These are stored as their quoted representation to support passing bindings, so make sure to account for this if implementing yourself.

If you want to override `changeset` but want to keep the default validation behavior, there is also the `Flint.Schema.validate_fields` function,
which accepts an `%Ecto.Changetset{}` and optionally bindings, and performs validations using the information stored in `__schema__(:validations)`.

## Generated Functions

`Flint` provides default implementations for the following functions for any schema declaration. Each of these is overridable.

* `changeset` - Creates a changeset by casting all fields and validating all that were marked as required. If a `:default` key is provided for a field, then any use of a bang (`!`) declaration will essentially be ignored since the cast will fall back to the default before any valdiations are performed.
* `new` - Creates a new changeset from the empty module struct and applies the changes (regardless of whether the changeset was valid).
* `new!` - Same as new, except raises if the changeset is not valid.

## Config

You can configure the default options set by `Flint`.

* `embeds_one`: The default arguments when using `embeds_one`. Defaults to `[defaults_to_struct: true, on_replace: :delete]`
* `embeds_one!`: The default arguments when using `embeds_one!`. Defaults to `[on_replace: :delete]`
* `embeds_many`: The default arguments when using `embeds_many` or `embeds_many!`. Defaults to `[on_replace: :delete]`
* `embeds_many!`: The default arguments when using `embeds_many!`. Defaults to `[on_replace: :delete]`
* `:enum`: The default arguments for an `Ecto.Enum` field. Defaults to `[embed_as: :dumped]`.
* `:aliases`: See [Aliases](#aliases)

You can also configure any aliases you want to use for schema validations.

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

<!-- END MODULEDOC -->