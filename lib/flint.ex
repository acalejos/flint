defmodule Flint do
  @moduledoc """
  #{File.cwd!() |> Path.join("README.md") |> File.read!() |> then(&Regex.run(~r/.*<!-- BEGIN MODULEDOC -->(?P<body>.*)<!-- END MODULEDOC -->.*/s, &1, capture: :all_but_first)) |> hd()}
  """

  defmacro __using__(opts) do
    {schema, opts} = Keyword.pop(opts, :schema)

    opts =
      Keyword.validate!(
        opts,
        primary_key: false,
        schema_prefix: nil,
        schema_context: nil,
        timestamp_opts: [type: :naive_datetime]
      )

    Module.register_attribute(__CALLER__.module, :required, accumulate: true)
    Module.register_attribute(__CALLER__.module, :validations, accumulate: true)
    Module.register_attribute(__CALLER__.module, :pre_transforms, accumulate: true)
    Module.register_attribute(__CALLER__.module, :post_transforms, accumulate: true)

    prelude =
      quote do
        alias Flint.Types.Union

        @after_compile Flint.Schema

        @behaviour Access

        @impl true
        defdelegate fetch(term, key), to: Map
        @impl true
        defdelegate get_and_update(term, key, fun), to: Map
        @impl true
        defdelegate pop(data, key), to: Map

        def __schema__(:required), do: @required |> Enum.reverse()
        def __schema__(:validations), do: @validations |> Enum.reverse()
        def __schema__(:pre_transforms), do: @pre_transforms |> Enum.reverse()
        def __schema__(:post_transforms), do: @post_transforms |> Enum.reverse()

        defdelegate changeset(schema, params \\ %{}, bindings \\ []), to: Flint.Pipeline
        def new(params \\ %{}, bindings \\ []), do: Flint.Schema.new(__MODULE__, params, bindings)

        def new!(params \\ %{}, bindings \\ []),
          do: Flint.Schema.new!(__MODULE__, params, bindings)

        defoverridable new: 0,
                       new: 1,
                       new: 2,
                       new!: 0,
                       new!: 1,
                       new!: 2,
                       changeset: 1,
                       changeset: 2,
                       changeset: 3

        if Code.ensure_loaded?(Jason) do
          defimpl Jason.Encoder do
            def encode(value, opts) do
              value |> Ecto.embedded_dump(:json) |> Jason.Encode.map(opts)
            end
          end
        end

        use Ecto.Schema
        import Ecto.Schema, except: [embedded_schema: 1]
        import Flint.Schema, only: [embedded_schema: 1]

        @schema_prefix unquote(opts[:schema_prefix])
        @schema_context unquote(opts[:schema_context])
        @timestamp_opts unquote(opts[:timestamp_opts])
        @primary_key unquote(opts[:primary_key])
      end

    if schema do
      quote do
        unquote(prelude)

        embedded_schema do
          unquote(schema)
        end
      end
    else
      quote do
        unquote(prelude)
      end
    end
  end
end
