# Flint

[![Flint version](https://img.shields.io/hexpm/v/flint.svg)](https://hex.pm/packages/flint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/flint/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/flint)](https://hex.pm/packages/flint)
[![Twitter Follow](https://img.shields.io/twitter/follow/ac_alejos?style=social)](https://twitter.com/ac_alejos)
<!-- BEGIN MODULEDOC -->

Declarative [`Ecto`](https://github.com/elixir-ecto/ecto) `embedded_schema`s for data validation, coercion, and manipulation.

## Feature Overview

* `!` Variants of Ecto `field`, `embeds_one`, and `embeds_many` macros to mark a field as required ([Required Fields](#required-fields))
* Colocated input transformations let you either transform input fields before validation or derive field values from other fields ([Derived Fields / Input Transformations](#derived-fields--input-transformations))
* Colocated validations, so you can define common validations alongside field declarations ([Validations](#field-validations))
* Colocated output transformations let you transform fields after validation ([Mappings / Output Transformations](#mappings--output-transformations))
* Extensible using the `Flint.Extension` module. Default extensions include:
  * `Accessible` - Adds `Access` implementation to the target schemas
  * `JSON` - Adds a custom JSON encoding (`Jason` and `Poison` supported) implementation to the target schemas
  * `Embedded` - Sets good default module attribute values used by `Ecto` specifically tailored for in-memory embedded schemas
  * And more!
* New [`Ecto.Schema` Reflection Functions](https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection)
  * `__schema__(:required)` - Returns list of fields marked as required (from `!` macros)
  * And more!
* Convenient generated function (`changeset`,`new`,`new!`,...) ([Generated Functions](#generated-functions))
* Configurable `Application`-wide defaults for `Ecto.Schema` API ([Config](#config))
* Conveniently create new `Ecto` types using the `Flint.Type` module and its  `deftype/2` macro ([`Flint.Type`](#flinttype))

## Installation

```elixir
def deps do
  [
    {:flint, "~> 0.6"},
    # If you want access to the `Typed` extension to add generated typespecs
    {:typed_ecto_schema, "~> 0.4", runtime: false}
  ]
end
```

## Motivation

`Flint` is built on top of Ecto and is meant to provide good defaults for using `embedded_schema`s for use outside of a database.
It also adds a bevy of convenient features to the existing `Ecto` API to make writing schemas and validations much quicker.

Of course, since you're using Ecto, you can use this for use as an ORM, but this is emphasizing the use of `embedded_schema`s as just more expressive and powerful maps while keeping compatibility with `Ecto.Changeset`, `Ecto.Type`, and all of the other benefits Ecto has to offer.

In particular, `Flint` focuses on making it more ergonomic to use `embedded_schema`s as a superset of Maps, so a `Flint.Schema` by default implements the `Access` behaviour and implements the `Jason.Encoder` protocol.

`Flint` also was made to leverage the distinction `Ecto` makes between the embedded representation of the schema and the dumped representation. This means that you can dictate how you want the Elixir-side representation to look, and then provide transformations
for how it should be dumped, which helps when you want the serialized representation to look different.

This is useful if you want to make changes in the server-side code without needing to change the client-side (or vice-versa). Or perhaps you want a mapped representation, where instead of an `Ecto.Enum` just converting its atom key to a string when dumped, it gets mapped to an integer, etc.

## Basic Usage

If you want to declare a schema with `Flint`, just `use Flint.Schema` within your module, and now you have access to `Flint`'s implementation of the
`embedded_schema/1` macro.  You can declare an `embedded_schema` within your module as you otherwise would with `Ecto`. Within the `embedded_schema/1` block, you also have access to `Flint`s implementations of `embeds_one`,`embeds_one!`,`embeds_many`, `embeds_many!`, `field`, and `field!`.

```elixir
defmodule User do
  use Flint.Schema

  embedded_schema do
    field! :username, :string
    field! :password, :string, redacted: true
    field :nickname, :string
  end
end
```

## `Flint` Types

`Flint` also comes with some types that are automatically aliased when you `use Flint`.

### `Union`

Union type for Ecto. Allows the field to be any of the specified types.

## `Flint.Type`

`Flint.Type` is meant to make writing new `Ecto` types require much less boilerplate, because you can base your type off of an existing type and only modify the callbacks that have different behavior.

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

### Examples

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

## Generated Functions

`Flint` provides default implementations for the following functions for any schema declaration. Each of these is overridable.

* `changeset` - Creates a changeset by casting all fields and validating all that were marked as required. If a `:default` key is provided for a field, then any use of a bang (`!`) declaration will essentially be ignored since the cast will fall back to the default before any validations are performed.
* `new` - Creates a new changeset from the empty module struct and applies the changes (regardless of whether the changeset was valid).
* `new!` - Same as new, except raises if the changeset is not valid.

## Flint Core

The core of Flint is the additional schema macros, which includes the bang (`!`) variants to mark
a field as required, and the added support of validations through `do` blocks to fields, as well
as the `Flint.Extension` API that allows extensions to define additional acceptable `field` options
and module attributes that can be reflected upon.

All other functionality comes in the form of `Flint` extensions.

At their core, the new `field` and `field!` macros' only additional functionality over the default `Ecto` macros is to store the allowed `Flint` options into module attributes which are exposed as new reflection functions.

The bulk of the work done in Flint with validations and transformations of data occurs in the generated `changeset` function, which leaves it up to the end user whether to use the default implementation, roll their own from scratch using the information exposed through the reflection functions, or do something in between (such as tuning which extensions you use).

When you `use Flint.Schema`, you declare an overridable `changeset` function for your schema module that by default just
delegates to the `Flint.Changeset.changeset/3` function.

The `Flint.Changeset.changeset/3` function operates as the following pipeline:

1. Cast all fields (including embeds)
2. Validate required fields ([Required Fields](#required-fields))

### Required Fields

`Flint` adds the convenience bang (`!`) macros (`embed_one!`,`embed_many!`, `field!`) for field declarations within your struct to declare a field as required within its `changeset` function.

`Flint` schemas also have a new reflection function in addition to the normal [`Ecto` reflection functions](https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection).

* `__schema__(:required)` -- Returns a list of all fields that were marked as required.

### Field Validations

#### `field` `do` Blocks

In `Flint`, the `field` and `field!` macros now accept an optional `do` block to define condition/error pairs.

```elixir
  embedded_schema do
    field! :type, :string do
      type not in ~w[elf human] -> "Expected elf or human, got: #{type}"
    end

    field! :age, :integer do
      age < 0 ->
        "Nobody can have a negative age"

      type == "elf" and age > max_elf_age ->
        "Attention! The elf has become a bug! Should be dead already!"

      type == "human" and age > max_human_age ->
        "Expected human to have up to #{max_human_age}, got: #{age}"
    end
  end
```

```elixir
max_elf_age = 400
max_human_age = 120
Character.new!(%{type: "elf", age: 10}, binding())
```

```elixir
** (ArgumentError) %Character{type: ["Expected elf or human, got: orc"], age: 10}
    (flint 0.0.1) lib/schema.ex:617: Flint.Schema.new!/3
    (elixir 1.15.7) src/elixir.erl:396: :elixir.eval_external_handler/3
    (stdlib 5.1.1) erl_eval.erl:750: :erl_eval.do_apply/7
    (elixir 1.15.7) src/elixir.erl:375: :elixir.eval_forms/4
    (elixir 1.15.7) lib/module/parallel_checker.ex:112: Module.ParallelChecker.verify/1
    lib/livebook/runtime/evaluator.ex:622: anonymous fn/3 in Livebook.Runtime.Evaluator.eval/4
    (elixir 1.15.7) lib/code.ex:574: Code.with_diagnostics/2
```

The `:do` block accepts a list of validation clauses, where is clause is of the form:

`failure condition -> Error Message`

In the `:do` block expressions, the same rules apply as mentioned across this documentation. You can pass
bindings to apply to the expression, and field name bindings will automatically be passed to the expression so you can just use the field names as variables.

Additionally, you will have access to all local functions and imported functions that the parent module would have, so you can write expressions as you would in the parent module.

The AST representations of these vaildations are stored in a module attribute and can be retrieved using

```elixir
__schema__(:blocks)
```

These validations are checked in the default `Flint.Changeset.changeset`.

#### Parameterized Validations

You can even parameterize the options passed to the validations:

```elixir
defmodule Person do
  use Flint.Schema

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

#### Validate With Respect to Other Fields

You might find yourself wishing to validate a field conditionally based on the values of other fields. In `Flint`, you
can do this with any validation! Since all validations already accept parameterized conditions, they also let you refer
to previously defined fields declared with `field` or `field!` macros. Just use a variable of the same name as the field(s) you want to refer to, and they will be bound to their respective variables.

## Extensions

Flint provides an extensible architecture using the `Flint.Extension` module.

In fact, most of the core features that `Flint` offers are written as `Flint` extensions.

The default extensions can be retrieved using `Flint.default_extensions()`

```elixir
Flint.default_extensions()

[
  Flint.Extensions.PreTransforms,
  Flint.Extensions.When,
  Flint.Extensions.EctoValidations,
  Flint.Extensions.PostTransforms,
  Flint.Extensions.Accessible,
  Flint.Extensions.Embedded,
  Flint.Extensions.JSON
]
```

To use extensions, you can specify them when using `Flint.Schema` in your module. If the `:extensions` option
is not provided, the default extensions will be used.

```elixir
defmodule MySchema do
  use Flint.Schema,
    extensions: [Accessible, JSON]

  embedded_schema do
    # Schema fields...
  end
end
```

**Note that you don't have to write the fully-qualified name for modules in the `Flint.Extensions` module.**

You can use `Flint.default_extensions()` to refer to the default extensions, which you will have to
explicitly add if you pass custom values to the `:extensions` option when using `Flint.Schema`, eg.

```elixir
defmodule MySchema do
  use Flint.Schema,
    extensions: Flint.default_extensions() ++ [MyExtension]

  embedded_schema do
    # Schema fields...
  end
end
```

You can also create custom extensions by `use`ing `Flint.Extension`. This allows you to add additional functionality or modify the behavior of Flint schemas according to your specific needs.

For more details on creating and using extensions, refer to the `Flint.Extension` module documentation.

## Aliases

If you don't like the name of an option, you can provide a compile-time list of aliases to map new option names to existing options
([Validation Options](#basic-validation-options) and [Transformation Options](#input-and-output-transformations)).

In your config, add an `:aliases` key with a `Keyword` value, where each key is the new alias, and the value is an existing option name.

For example, these are default aliases implemented in `Flint`:

```elixir
config Flint, aliases: [
    lt: :less_than,
    gt: :greater_than,
    le: :less_than_or_equal_to,
    ge: :greater_than_or_equal_to,
    eq: :equal_to,
    ne: :not_equal_to
  ]
```

**NOTE** If you add your own aliases and want to keep these above defaults, you will have to add them manually to your aliases.

## Config

You can configure the default options set by `Flint`.

* `embeds_one`: The default arguments when using `embeds_one`. Defaults to `[defaults_to_struct: true, on_replace: :delete]`
* `embeds_one!`: The default arguments when using `embeds_one!`. Defaults to `[on_replace: :delete]`
* `embeds_many`: The default arguments when using `embeds_many` or `embeds_many!`. Defaults to `[on_replace: :delete]`
* `embeds_many!`: The default arguments when using `embeds_many!`. Defaults to `[on_replace: :delete]`
* `:aliases`: [Aliases](#aliases)

You can also configure any aliases you want to use for schema validations.

## Embedded vs Dumped Representations

`Flint` takes advantage of the distinction `Ecto` makes between an `embedded_schema`'s embedded and dumped representations.

For example, `Flint` provides the `Flint.Types.Enum` type, which are `Ecto.Enum`s where, when given values that are `Keyword` (rather than just lists of atoms) will have their keys
be the embedded representation and will have the values be the dumped representation.

```elixir
defmodule Book do
  use Flint.Schema, schema: [
    field(:genre, Flint.Types.Enum, values: [biography: 0, science_fiction: 1, fantasy: 2, mystery: 3])
  ]
end

book = Book.new(%{genre: "biography"})
# %Book{genre: :biography}

Flint.Schema.dump(book)
# %{genre: 0}
```

In this example, you can see how you can share multiple representations of the same data using this distinction.

You can also implement your own `Ecto.Type` and further customize this (see [`Flint.Type`](#flinttype)):

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

You can view the [Notebooks folder](https://github.com/acalejos/flint/tree/main/notebooks) for some examples in Livebook.

You can also look at [Merquery](https://github.com/acalejos/merquery/tree/main/lib/merquery/schemas) for a real, comprehensive
example of how to use `Flint`.

<!-- END MODULEDOC -->