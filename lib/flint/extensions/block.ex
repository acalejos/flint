defmodule Flint.Extensions.Block do
  @moduledoc """
  Adds support for `do` block in `field` and `field!` to add `validation_condition -> error_message` pairs to the field.

  Block validations can be specified using `do` blocks in `field` and `field!`. These are specified as lists of `error_condition -> error_message` pairs. If the error condition returns `true`, then the corresponding `error_message` will be inserted into the changeset when using the generated `changeset`, `new`, and `new!` functions.

  Within these validations, you can pass custom bindings, meaning that you can define these validations with respect to variables only available at runtime.

  In addition to any bindings you pass, the calues of the fields themselves will be available as a variable with the same name as the field.

  You can also refer to local and imported / aliased function within these validations as well.
  """
  use Flint.Extension

  option :__block__

  @doc """
  Uses the quoted expressions from the `Flint.Schema.field` and `Flint.Schema.field!`
  `do` blocks to validate the changeset.

  You can optionally pass bindings to be added to the evaluation context.
  """
  @impl true
  def changeset(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_validations =
      module.__schema__(:extra_options)
      |> Enum.map(fn {field, opts} -> {field, Keyword.take(opts, __MODULE__.option_names())} end)

    for {field, block} <- all_validations, reduce: changeset do
      changeset ->
        block = Keyword.get(block, :__block__) || []
        bindings = bindings ++ Enum.into(changeset.changes, [])

        block
        |> Enum.with_index()
        |> Enum.reduce(changeset, fn
          {{:->, _, [[quoted_condition], quoted_err]}, index}, chngset ->
            try do
              {invalid?, _bindings} =
                Code.eval_quoted(quoted_condition, bindings, env)

              invalid? =
                if is_function(invalid?) do
                  case Function.info(invalid?, :arity) do
                    {:arity, 0} ->
                      apply(invalid?, [])

                    {:arity, 1} when not is_nil(field) ->
                      apply(invalid?, [Ecto.Changeset.fetch_change!(changeset, field)])

                    _ ->
                      raise ArgumentError,
                            "Anonymous functions in validation clause must be either 0-arity or an input value for the field must be provided."
                  end
                else
                  invalid?
                end

              {err_msg, _bindings} = Code.eval_quoted(quoted_err, bindings, env)

              if invalid? do
                Ecto.Changeset.add_error(chngset, field, err_msg,
                  validation: :block,
                  clause: index + 1
                )
              else
                chngset
              end
            rescue
              _ ->
                Ecto.Changeset.add_error(
                  chngset,
                  field,
                  "Error evaluating expression in Clause ##{index + 1} of `do:` block"
                )
            end

          _, chngset ->
            Ecto.Changeset.add_error(
              chngset,
              field,
              "Bad expression in `field do:`. All clauses should be of the format `condition` -> `Error Message`"
            )
        end)
    end
  end

  defmacro field(name, type, do: block) when is_list(block) do
    quote do
      field(unquote(name), unquote(type), [], do: unquote(block))
    end
  end

  defmacro field(name, type, opts) do
    quote do
      Flint.Schema.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field(name, type, opts, do: block) do
    opts = [{:__block__, block} | opts]

    quote do
      Flint.Schema.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field!(name, type, do: block) do
    quote do
      field!(unquote(name), unquote(type), [], do: unquote(block))
    end
  end

  defmacro field!(name, type, opts) do
    quote do
      Flint.Schema.field!(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field!(name, type, opts, do: block) do
    # make_required(__CALLER__.module, name)
    opts = [{:__block__, block} | opts]

    quote do
      Flint.Schema.field!(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro embedded_schema(do: block) do
    {mod, _macros} = Flint.Extension.__context__(__CALLER__, __MODULE__)

    quote do
      unquote(mod).embedded_schema do
        import unquote(mod),
          except: [field: 3, field!: 3]

        import unquote(__MODULE__), only: [field!: 3, field!: 4, field: 3, field: 4]
        unquote(block)
      end
    end
  end

  defmacro __using__(_opts) do
    {mod, macros} = Flint.Extension.__embedded_schema__(__CALLER__, __MODULE__)

    quote do
      import unquote(mod), except: unquote(macros)
      import unquote(__MODULE__), only: [embedded_schema: 1]
    end
  end
end
