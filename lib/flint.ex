defmodule Flint do
  @moduledoc """
  #{File.cwd!() |> Path.join("README.md") |> File.read!() |> then(&Regex.run(~r/.*<!-- BEGIN MODULEDOC -->(?P<body>.*)<!-- END MODULEDOC -->.*/s, &1, capture: :all_but_first)) |> hd()}
  """

  defmacro __using__(opts \\ [], schema: schema) do
    opts =
      Keyword.validate!(opts,
        primary_key: false,
        schema_prefix: nil,
        schema_context: nil,
        timestamp_opts: [type: :naive_datetime]
      )

    Module.register_attribute(__CALLER__.module, :required, accumulate: true)

    quote do
      @behaviour Access

      defdelegate fetch(term, key), to: Map
      defdelegate get_and_update(term, key, fun), to: Map
      defdelegate pop(data, key), to: Map

      use Ecto.Schema
      import Ecto.Changeset

      @schema_prefix unquote(opts[:schema_prefix])
      @schema_context unquote(opts[:schema_context])
      @timestamp_opts unquote(opts[:timestamp_opts])
      @primary_key unquote(opts[:primary_key])
      embedded_schema do
        import Ecto.Schema,
          except: [
            embeds_one: 2,
            embeds_one: 3,
            embeds_one: 4,
            embeds_many: 2,
            embeds_many: 3,
            embeds_many: 4,
            field: 2,
            field: 3
          ]

        import Flint.Schema, only: :macros

        unquote(schema)
      end

      def __schema__(:required), do: @required

      defdelegate changeset(schema, params \\ %{}), to: Flint.Schema
      def new(params \\ %{}), do: Flint.Schema.new(__MODULE__, params)
      def new!(params \\ %{}), do: Flint.Schema.new!(__MODULE__, params)
      defoverridable new: 0, new: 1, new!: 0, new!: 1, changeset: 1, changeset: 2

      if Code.ensure_loaded?(Jason) do
        defimpl Jason.Encoder do
          def encode(value, opts) do
            value |> Ecto.embedded_dump(:json) |> Jason.Encode.map(opts)
          end
        end
      end
    end
  end
end
