defmodule Flint.Extensions.PreTransforms do
  @moduledoc """
  The `PreTransforms` provides a convenient `:derive` option to express how the field is computed.

  **By default, this occurs after casting and before validations.**

  `derived` fields let you define expressions with support for custom bindings to include any
  `field` declarations that occur before the current field.

  `:derive` will automatically put the result of the input expression into the field value.
  By default, this occurs before any other validation, so you can still have access to `field`
  bindings and even the current computed field value (eg. within a `:when` validation from the
  `When` extension).

  You can define a `derived` field with respect to the field itself, in which case it acts as
  transformation. Typically in `Ecto`, incoming transformations of this support would happen
  at the `cast` step, which means the behavior is determined by the type in which you are casting into.
  `:derive` lets you apply a transformation after casting to change that behavior
  without changing the underlying allowed type.

  You can also define a `derived` field with an expression that does not depend on the field,
  in which case it is suggested that you use the `field` macro instead of `field!` since any input
  in that case would be thrashed by the derived value. This means that a field can be completely
  determined as a product of other fields!

  ```elixir
  defmodule Test do
    use Flint.Schema

    embedded_schema do
      field! :category, Union, oneof: [Ecto.Enum, :decimal, :integer], values: [a: 1, b: 2, c: 3]
      field! :rating, :integer, when: category == target_category
      field :score, :integer, derive: rating + category, gt: 1, lt: 100, when: score > rating
    end
  end
  ```

  ```elixir
  Test.new!(%{category: 1, rating: 80}, target_category: 1)

  # %Test{category: 1, rating: 80, score: 81}
  ```
  """
  use Flint.Extension
  import Ecto.Changeset

  option :derive

  @doc """
  Applies transformations to each field according to the `:derive` options passed in the schema specification.

  These transformations are applied after casting, but before validations when used within the default `Flint.Changeset.changeset` implementation.

  Accepts optional bindings which are passed to evaluated code.
  """
  @impl true
  def changeset(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_pre_transforms =
      module.__schema__(:extra_options)
      |> Enum.flat_map(fn {field, opts} ->
        if field in Map.keys(changeset.changes) do
          [{field, Keyword.take(opts, __MODULE__.option_names())}]
        else
          []
        end
      end)

    for {field, pre_transforms} <- all_pre_transforms, reduce: changeset do
      changeset ->
        derived_expression = Keyword.get(pre_transforms, :derive)
        bindings = bindings ++ Enum.into(changeset.changes, [])

        if derived_expression do
          {derived_value, _bindings} = Code.eval_quoted(derived_expression, bindings, env)

          derived_value =
            if is_function(derived_value) do
              case Function.info(derived_value, :arity) do
                {:arity, 0} ->
                  apply(derived_value, [])

                {:arity, 1} when not is_nil(field) ->
                  apply(derived_value, [
                    fetch_change!(changeset, field)
                  ])

                _ ->
                  raise ArgumentError,
                        "Anonymous functions provided to `:derive` must be either 0-arity or an input value for the field must be provided."
              end
            else
              derived_value
            end

          put_change(changeset, field, derived_value)
        else
          changeset
        end
    end
  end
end
