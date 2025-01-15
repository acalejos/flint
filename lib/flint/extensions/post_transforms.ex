defmodule Flint.Extensions.PostTransforms do
  @moduledoc ~S"""
  The `PostTransforms` extension adds the `:map` option to `Flint` schemas.

  This works similarly to the `PreTransforms` extension, but uses the `:map` option rather than
  the `:derive` option used by `PreTransforms`, and by default, applies to the field after all validations.

  The same caveats apply to the `:map` expression as all other expressions, with the exception that the
  `:map` function **only** accepts arity-1 anonymous functions or non-anonymous function expressions
  (eg. using variable replacement).

  In the following example, `:derived` is used to normalize incoming strings to downcase to prepare for
  the validation, then the output is mapped to the uppercase string using the `:map` option.

  ```elixir
  defmodule Character do
    use Flint.Schema

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
  """
  use Flint.Extension
  import Ecto.Changeset

  option :map

  @doc """
  Applies transformations to each field according to the `:map` options passed in the schema specification.

  These transformations are applied after validations when used within the default `Flint.Changeset.changeset` implementation.

  Accepts optional bindings which are passed to evaluated code.
  """
  @impl true
  def changeset(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_post_transforms =
      module.__schema__(:extra_options)
      |> Enum.flat_map(fn {field, opts} ->
        if field in Map.keys(changeset.changes) do
          [{field, Keyword.take(opts, __MODULE__.option_names())}]
        else
          []
        end
      end)

    for {field, post_transforms} <- all_post_transforms, reduce: changeset do
      changeset ->
        {map_expression, _post_transforms} = Keyword.pop(post_transforms, :map)
        bindings = bindings ++ Enum.into(changeset.changes, [])

        if is_nil(map_expression) do
          changeset
        else
          {mapped, _bindings} = Code.eval_quoted(map_expression, bindings, env)

          mapped =
            if is_function(mapped) do
              case Function.info(mapped, :arity) do
                {:arity, 1} when not is_nil(field) ->
                  apply(mapped, [fetch_change!(changeset, field)])

                {:arity, 1} when is_nil(field) ->
                  nil

                _ ->
                  raise ArgumentError,
                        ":map option only accepts arity-1 anonymous function"
              end
            else
              mapped
            end

          put_change(changeset, field, mapped)
        end
    end
  end
end
