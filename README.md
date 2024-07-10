# Flint

[![Flint version](https://img.shields.io/hexpm/v/flint.svg)](https://hex.pm/packages/flint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/flint/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/flint)](https://hex.pm/packages/flint)
[![Twitter Follow](https://img.shields.io/twitter/follow/ac_alejos?style=social)](https://twitter.com/ac_alejos)
<!-- BEGIN MODULEDOC -->

Practical [`Ecto`](https://github.com/elixir-ecto/ecto) `embedded_schema`s for data validation, coercion, and manipulation.

## Feature Overview

* `!` Variants of Ecto `field`, `embeds_one`, and `embeds_many` macros to mark a field as required ([Required Fields](#required-fields))
* Colocated input transformations let you either transform input fields before validation or derive field values from other fields ([Derived Fields / Input Transformations](#derived-fields--input-transformations))
* Colocated validations, so you can define common validations alongside field declarations ([Validations](#field-validations))
* Colocated output transformations let you transform fields after validation ([Mappings / Output Transformations](#mappings--output-transformations))
* Adds `Access` implementation to all schemas
* Adds `Jason.Encoder` implementation to all schemas
* New [`Ecto.Schema` Reflection Functions](https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection)
  * `__schema__(:required)` - Returns list of fields marked as required (from `!` macros)
  * `__schema__(:pre_transforms` - `Keyword` mapping of fields to pre-transformations (currently only `:derive` option)
  * `__schema__(:validations)` - `Keyword` mapping of fields to validations
  * `__schema__(:post_transforms` - `Keyword` mapping of fields to post-transformations (currently only `:map` option)
* Convenient generated function (`changeset`,`new`,`new!`,...) ([Generated Functions](#generated-functions))
* Configurable `Application`-wide defaults for `Ecto.Schema` API ([Config](#config))

## Installation

```elixir
def deps do
  [
    {:flint, github: "acalejos/flint"}
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

## `Flint` Types

`Flint` also comes with some types that are automatically aliased when you `use Flint`.

### `Union`

Union type for Ecto. Allows the field to be any of the specified types.

## Generated Functions

`Flint` provides default implementations for the following functions for any schema declaration. Each of these is overridable.

* `changeset` - Creates a changeset by casting all fields and validating all that were marked as required. If a `:default` key is provided for a field, then any use of a bang (`!`) declaration will essentially be ignored since the cast will fall back to the default before any validations are performed.
* `new` - Creates a new changeset from the empty module struct and applies the changes (regardless of whether the changeset was valid).
* `new!` - Same as new, except raises if the changeset is not valid.

### Changeset

At their core, the new `field` and `field!` macros' only additional functionality over the default `Ecto` macros
is to store the allowed `Flint` options into module attritbutes which are exposed as new reflection functions.

The bulk of the work done in Flint with validations and transformations of data occurs in the generated `changeset`
function, which leaves it up to the end user whether to use the default implementation, roll their own from scratch
using the information exposed through the reflection functions, or do something in between (such as using the `Flint.Changeset` APIs).

When you `use Flint`, you declare an overridable `changeset` function for your schema module that by default just
delegates to the `Flint.Changeset.changeset/3` function.

The `Flint.Changeset.changeset/3` function operates as the following pipeline:

1. Cast all fields (including embeds)
2. Validate required fields ([Required Fields](#required-fields))
3. Apply pre-transformations ([Derived Fields / Input Transformations](#derived-fields--input-transformations))
4. Apply field validations ([Validations](#field-validations))
5. Apply post-transformations ([Mappings / Output Transformations](#mappings--output-transformations))

If you wish to compose your own `changeset` function, each of these steps has its own API, either from `Ecto` itself
or exposed through `Flint`:

1. [`Ecto.Changeset.cast/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#cast/4) / [`Ecto.Changeset.cast_embed/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#cast_embed/3)
2. [`Ecto.Changeset.validate_required/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_required/3)
3. `Flint.Changeset.apply_pre_transforms/2`
4. `Flint.Changeset.apply_validations/2`
5. `Flint.Changeset.apply_post_transforms/2`

## Required Fields

`Flint` adds the convenience bang (`!`) macros (`embed_one!`,`embed_many!`, `field!`) for field declarations within your struct to declare a field as required within its `changeset` function.

`Flint` schemas also have a new reflection function in addition to the normal [`Ecto` reflection functions](https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection).

* `__schema__(:required)` -- Returns a list of all fields that were marked as required.

## Derived Fields / Input Transformations

`Flint` provides a convenient `:derive` option to express how the field is computed.

**This occurs after casting and before validations.**

Much like the [previous section](#validate-with-respect-to-other-fields), `derived` fields let you define
expressions with support for custom bindings to include any `field` declarations that occur before the current field.

`:derive` will automatically put the result of the input expression into the field value. This occurs before
any other validation, so you can still have access to `field` bindings and even the current computed field value
within a `:when` validation.

You can define a `derived` field with respect to the field itself, in which case it acts as transformation. Typically in
`Ecto`, incoming transformations of this support would happen at the `cast` step, which means the behavior is determined
by the type in which you are casting into. `:derive` lets you apply a transformation after casting to change that behavior
without changing the underlying allowed type.

You can also define a `derived` field with an expression that does not depend on the field, in which case it is
suggested that you use the `field` macro instead of `field!` since any input in that case would be thrashed by
the derived value. This means that a field can be completely determined as a product of other fields!

```elixir
defmodule Test do
  use Flint

  embedded_schema do
    field! :category, Union, oneof: [Ecto.Enum, :decimal, :integer], values: [a: 1, b: 2, c: 3]
    field! :rating, :integer, when: category == target_category
    field :score, derive: rating + category, :integer, gt: 1, lt: 100, when: score > rating
  end
end
```

```elixir
Test.new!(%{category: 1, rating: 80}, target_category: 1)

# %Test{category: 1, rating: 80, score: 81}
```

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

### Validate With Respect to Other Fields

You might find yourself wishing to validate a field conditionally based on the values of other fields. In `Flint`, you
can do this with any validation! Since all validations already accept parameterized conditions, they also let you refer
to previously defined fields declared with `field` or `field!` macros. Just use a variable of the same name as the field(s) you want to refer to, and they will be bound to their respective variables.

Additionally, `:when` lets you define an arbitrary boolean expression that will be evaluated and pass the validation if it
evaluates to a truthy value. You may pass bindings to this condition just as explained [above](#parameterized-validations), and
refer to previously defined fields as just discussed, but uniquely, `:when` also lets you refer to the current `field` in which
the `:when` condition is defined. Theoretically, you could write many of the other validations using `:when`, but you will
receive worse error messages with `:when` than with the dedicated validations.

```elixir
defmodule Test do
  use Flint

  embedded_schema do
    field! :category, Union, oneof: [Ecto.Enum, :decimal, :integer], values: [a: 1, b: 2, c: 3]
    field! :rating, :integer, when: category == target_category
    field! :score, :integer, gt: 1, lt: 100, when: score > rating
  end
end
```

```elixir
> Test.new!(%{category: :a, rating: 80, score: 10}, target_category: :a)

** (ArgumentError) %Test{category: :a, rating: 80, score: ["Failed `:when` validation"]}
    (flint 0.0.1) lib/schema.ex:406: Flint.Schema.new!/3
    (elixir 1.15.7) src/elixir.erl:396: :elixir.eval_external_handler/3
    (stdlib 5.1.1) erl_eval.erl:750: :erl_eval.do_apply/7
    (elixir 1.15.7) src/elixir.erl:375: :elixir.eval_forms/4
    (elixir 1.15.7) lib/module/parallel_checker.ex:112: Module.ParallelChecker.verify/1
    lib/livebook/runtime/evaluator.ex:622: anonymous fn/3 in Livebook.Runtime.Evaluator.eval/4
    (elixir 1.15.7) lib/code.ex:574: Code.with_diagnostics/2
```

### Basic Validation Options

`Flint` provides some shorthand options for common validation functions (mostly taken from `Ecto.Changeset`)

* `:greater_than` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:less_than` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:less_than_or_equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:greater_than_or_equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:not_equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
* `:format` ([`Ecto.Changeset.validate_format/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_format/4))
* `:subset_of` ([`Ecto.Changeset.validate_subset/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_subset/4))
* `:in` ([`Ecto.Changeset.validate_inlusion/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_inclusion/4))
* `:not_in` ([`Ecto.Changeset.validate_exclusion/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_exclusion/4))
* `:is` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:min` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:max` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:count` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
* `:when` - Let's you define an arbitrary boolean condition on the field which can refer to any `field` defined above it or itself. **NOTE** The `:when` option will output a generic error on failure, so if verbosity is desired, an [advanced validation](#advanced-validations) is more appropriate.

### Advanced Validations

In `Flint`, the `field` and `field!` macros also now accept an optional `do` block to define condition/error pairs.

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
bindings to apply to the expression, and field name bindings will automatically be passed to the expression
so you can just use the field names as variables.

Additionally, you will have access to all local functions and imported functions that the parent module would
have, so you can write expressions as you would in the parent module.

### `__schema__(:validations)`

Since validations are enforced through the generated `changeset` functions, if you override this function you will not get the benefits
of the validations.

If you want to implement your own, you can use `__schema__(:validations)` which is an added reflection function that stores validations.

**NOTE** These are stored as their quoted representation to support passing bindings, so make sure to account for this if implementing yourself.

If you want to override `changeset` but want to keep the default validation behavior, there is also the `Flint.Schema.validate_fields` function,
which accepts an `%Ecto.Changetset{}` and optionally bindings, and performs validations using the information stored in `__schema__(:validations)`.

## Mappings / Output Transformations

`Flint` also lets you declare a mapping to apply to the field after all validations. The same caveats apply to the
`:map` expression as all other expressions, with the exception that the `:map` function **only** accepts arity-1 anonymous functions
or non-anonymous function expressions (eg. using variable replacement).

In the following example, `computed` is used to normalize incoming strings to downcase to prepare for the validation, then the output
is mapped to the uppercase string using the `:map` option.

```elixir
defmodule Character do
  use Flint
  
  embedded_schema do
    field! :type, :string, derive: &String.downcase/1, map: String.upcase(type) do
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
end
```

```elixir
max_elf_age = 400
max_human_age = 120
Character.new!(%{type: "Elf", age: 10}, binding())
```

```elixir
%Character{type: "ELF", age: 10}
```

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
* `:enum`: The default arguments for an `Ecto.Enum` field. Defaults to `[embed_as: :dumped]`.
* `:aliases`: [Aliases](#aliases)

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

In this example, you can how you can share multiple representations of the same data using this distinction.

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