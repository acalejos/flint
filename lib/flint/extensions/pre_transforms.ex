defmodule Flint.Extensions.PreTransforms do
  use Flint.Extension
  import Ecto.Changeset

  option :derive

  @doc """
  Applies transformations to each field according to the `:derive` options passed in the schema specification.

  These transformations are applied after casting, but before validations when used within the default `Flint.Pipeline.changeset` implementation.

  Accepts optional bindings which are passed to evaluated code.
  """
  def apply_pre_transforms(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_pre_transforms =
      module.__schema__(:extra_options)
      |> Enum.map(fn {field, opts} -> {field, Keyword.take(opts, __MODULE__.option_names())} end)

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

  defmacro __using__(_opts) do
    quote do
      def changeset(schema, params \\ %{}, bindings \\ []) do
        changeset =
          super(schema, params, bindings)

        Flint.Extensions.PreTransforms.apply_pre_transforms(changeset, bindings)
      end

      defoverridable changeset: 1,
                     changeset: 2,
                     changeset: 3
    end
  end
end
