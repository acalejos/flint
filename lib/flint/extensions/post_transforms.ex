defmodule Flint.Extensions.PostTransforms do
  use Flint.Extension
  import Ecto.Changeset

  option :map

  @doc """
  Applies transformations to each field according to the `:map` options passed in the schema specification.

  These transformations are applied after validations when used within the default `Flint.Pipeline.changeset` implementation.

  Accepts optional bindings which are passed to evaluated code.
  """
  def apply_post_transforms(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_post_transforms =
      module.__schema__(:extra_options)
      |> Enum.map(fn {field, opts} -> {field, Keyword.take(opts, __MODULE__.option_names())} end)

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

  defmacro __using__(_opts) do
    quote do
      def changeset(schema, params \\ %{}, bindings \\ []) do
        changeset =
          super(schema, params, bindings)

        Flint.Extensions.PostTransforms.apply_post_transforms(changeset, bindings)
      end

      defoverridable changeset: 1,
                     changeset: 2,
                     changeset: 3
    end
  end
end
