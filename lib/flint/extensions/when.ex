defmodule Flint.Extensions.When do
  @moduledoc """
  The `When` extension adds the `:when` option to `Flint` schemas.

  `:when` lets you define an arbitrary boolean expression that will be evaluated and pass the validation if it
  evaluates to a truthy value. You may pass bindings to this condition and
  refer to previously defined fields. `:when` also lets you refer to the current `field` in which
  the `:when` condition is defined. Theoretically, you could write many of the other validations using `:when`, but you will
  receive worse error messages with `:when` than with the dedicated validations.

  ```elixir
  defmodule Test do
    use Flint.Schema

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
  """
  use Flint.Extension
  import Ecto.Changeset

  option :when

  @impl true
  def changeset(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_validations =
      module.__schema__(:extra_options)
      |> Enum.map(fn {field, opts} -> {field, Keyword.take(opts, __MODULE__.option_names())} end)

    for {field, validations} <- all_validations, reduce: changeset do
      changeset ->
        bindings = bindings ++ Enum.into(changeset.changes, [])
        when_condition = Keyword.get(validations, :when)

        if not is_nil(when_condition) do
          {validate_when_condition, _bindings} =
            try do
              Code.eval_quoted(
                when_condition,
                bindings,
                env
              )
            rescue
              _ ->
                {false, nil}
            end

          if validate_when_condition do
            changeset
          else
            add_error(changeset, field, "Failed `:when` validation")
          end
        else
          changeset
        end
    end
  end
end
