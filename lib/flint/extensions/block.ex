defmodule Flint.Extensions.Block do
  @moduledoc """
  Adds support for `do` block in `field` and `field!` to add `validation_condition -> error_message` pairs to the field.

  Block validations can be specified using `do` blocks in `field` and `field!`. These are specified as lists of
  `error_condition -> evaluation` pairs. If the error condition returns `true`, then the corresponding expression will
  be evaluated. That expression must return one of the following:

  * `:ok`
  * `nil`
  * `{:error, reason}`
  * `:error`
  * `reason` when `reason` is a binary

  The first two results are considered `pass` results, while the last three are considered `fail` results, where the `reason`
  will be inserted as an error in the changeset when using the generated `changeset`, `new`, and `new!` functions.

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
      |> Enum.flat_map(fn {field, opts} ->
        if field in Map.keys(changeset.changes) do
          [{field, Keyword.take(opts, __MODULE__.option_names())}]
        else
          []
        end
      end)

    for {field, block} <- all_validations, reduce: changeset do
      changeset ->
        block = Keyword.get(block, :__block__) || []

        bindings =
          bindings ++ Enum.into(changeset.changes, [])

        block
        |> Enum.with_index()
        |> Enum.reduce(changeset, fn
          {{:->, _, [[quoted_condition], expression]}, index}, chngset ->
            case eval_quoted(quoted_condition, bindings, env) do
              {:ok, {continue?, _bindings}} ->
                continue? =
                  if is_function(continue?) do
                    case Function.info(continue?, :arity) do
                      {:arity, 0} ->
                        apply(continue?, [])

                      {:arity, 1} when not is_nil(field) ->
                        apply(continue?, [Ecto.Changeset.fetch_change!(changeset, field)])

                      _ ->
                        raise ArgumentError,
                              "Anonymous functions in validation clause must be either 0-arity or an input value for the field must be provided."
                    end
                  else
                    continue?
                  end

                if continue? do
                  case eval_quoted(expression, bindings, env) do
                    {:ok, {good, _bindings}} when good in [:ok, nil] ->
                      changeset

                    {:ok, {<<err_msg::binary>>, _bindings}} ->
                      Ecto.Changeset.add_error(chngset, field, err_msg,
                        validation: :block,
                        clause: index + 1
                      )

                    {:ok, {{:error, err_msg}, _bindings}} ->
                      Ecto.Changeset.add_error(chngset, field, err_msg,
                        validation: :block,
                        clause: index + 1
                      )

                    {:ok, {:error, _bindings}} ->
                      Ecto.Changeset.add_error(
                        chngset,
                        field,
                        "Error validating expression in Clause ##{index + 1} of `do:` block"
                      )

                    :error ->
                      Ecto.Changeset.add_error(
                        chngset,
                        field,
                        "Error evaluating expression in Clause ##{index + 1} of `do:` block"
                      )

                    _ ->
                      raise ArgumentError,
                            "Bad expression in `field do:`. All clauses should be of the format `condition` -> `expression`"
                  end
                else
                  chngset
                end

              :error ->
                Ecto.Changeset.add_error(
                  chngset,
                  field,
                  "Error evaluating expression in Clause ##{index + 1} of `do:` block"
                )
            end

          _, _chngset ->
            raise ArgumentError,
                  "Bad expression in `field do:`. All clauses should be of the format `condition` -> `expression`"
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
