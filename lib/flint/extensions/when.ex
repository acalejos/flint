defmodule Flint.Extensions.When do
  use Flint.Extension
  import Ecto.Changeset

  option :when

  def validate_when_condition(changeset, bindings \\ []) do
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

  defmacro __using__(_opts) do
    quote do
      def changeset(schema, params \\ %{}, bindings \\ []) do
        changeset =
          super(schema, params, bindings)

        Flint.Extensions.When.validate_when_condition(changeset, bindings)
      end

      defoverridable changeset: 1,
                     changeset: 2,
                     changeset: 3
    end
  end
end
