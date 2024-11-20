defmodule Flint.Extensions.EctoValidations do
  @moduledoc """
  Shorthand options for common validations found in `Ecto.Changeset`

  Just passthrough the option for the appropriate validation and this extension
  will take care of calling the corresponding function from `Ecto.Changeset` on
  your data.

  ## Options

  * `:greater_than` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
  * `:less_than` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
  * `:less_than_or_equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
  * `:greater_than_or_equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
  * `:equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
  * `:not_equal_to` ([`Ecto.Changeset.validate_number/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_number/3-options))
  * `:format` ([`Ecto.Changeset.validate_format/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_format/4))
  * `:subset_of` ([`Ecto.Changeset.validate_subset/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_subset/4))
  * `:in` ([`Ecto.Changeset.validate_inlusion/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_inclusion/4))
  * `:not_in` ([`Ecto.Changeset.validate_exclusion/4`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_exclusion/4))
  * `:is` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
  * `:min` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
  * `:max` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))
  * `:count` ([`Ecto.Changeset.validate_length/3`](https://hexdocs.pm/ecto/Ecto.Changeset.html#validate_length/3-options))

  ## Aliases

  By default, the following aliases are also available for convenience:

  ```elixir
  config Flint, aliases: [
    lt: :less_than,
    gt: :greater_than,
    le: :less_than_or_equal_to,
    ge: :greater_than_or_equal_to,
    eq: :equal_to,
    ne: :not_equal_to
  ]
  ```

  ## Example

  ```elixir
  defmodule Person do
    use Flint.Schema

    embedded_schema do
      field! :first_name, :string,  max: 10, min: 5
      field! :last_name, :string, min: 5, max: 10
      field :favorite_colors, {:array, :string}, subset_of: ["red", "blue", "green"]
      field! :age, :integer, greater_than: 0, less_than: max_age
    end
  end
  ```

  ```elixir
  Person.changeset(
    %Person{},
    %{first_name: "Bob", last_name: "Smith", favorite_colors: ["red", "blue", "pink"], age: 101},
    [max_age: 100]
  )
  ```

  ```elixir
  #Ecto.Changeset<
    action: nil,
    changes: %{
      age: 101,
      first_name: "Bob",
      last_name: "Smith",
      favorite_colors: ["red", "blue", "pink"]
    },
    errors: [
      first_name: {"should be at least %{count} character(s)",
      [count: 5, validation: :length, kind: :min, type: :string]},
      favorite_colors: {"has an invalid entry", [validation: :subset, enum: ["red", "blue", "green"]]},
      age: {"must be less than %{number}", [validation: :number, kind: :less_than, number: 100]}
    ],
    data: #Person<>,
    valid?: false,
    ...
  >
  ```
  """
  use Flint.Extension

  # validate_number
  option :greater_than
  option :less_than
  option :less_than_or_equal_to
  option :greater_than_or_equal_to
  option :equal_to
  option :not_equal_to
  # validate_format
  option :format
  # validate_subset
  option :subset_of
  # validate_inclusion
  option :in
  # validate_excludion
  option :not_in
  # validate_length
  option :is
  option :min
  option :max
  option :count

  @doc """
  Applies validations to each field according to the options passed in the schema specification.

  See the `Field Validations` section of the README for more information on validation details.
  """
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

        validations =
          validations
          |> Enum.map(fn
            {k, v} ->
              {result, _bindings} = Code.eval_quoted(v, bindings, env)
              {k, result}
          end)

        {validate_length_args, validations} =
          Keyword.split(validations, [:is, :min, :max, :count])

        {validate_number_args, validations} =
          Keyword.split(validations, [
            :less_than,
            :greater_than,
            :less_than_or_equal_to,
            :greater_than_or_equal_to,
            :equal_to,
            :not_equal_to
          ])

        {validate_subset_arg, validations} = Keyword.pop(validations, :subset_of)
        {validate_inclusion_arg, validations} = Keyword.pop(validations, :in)
        {validate_exclusion_arg, validations} = Keyword.pop(validations, :not_in)
        {validate_format_arg, _validations} = Keyword.pop(validations, :format)

        validation_args =
          [
            validate_inclusion: validate_inclusion_arg,
            validate_exclusion: validate_exclusion_arg,
            validate_number: validate_number_args,
            validate_length: validate_length_args,
            validate_format: validate_format_arg,
            validate_subset: validate_subset_arg
          ]
          |> Enum.map(fn
            {k, args} when k in [:validate_number, :validate_length] ->
              {k, Enum.reject(args, fn {_k, v} -> is_nil(v) end)}

            other ->
              other
          end)

        Enum.reduce(validation_args, changeset, fn
          {_func, nil}, chngset ->
            chngset

          {_func, []}, chngset ->
            chngset

          {func, arg}, chngset ->
            apply(Ecto.Changeset, func, [chngset, field, arg])
        end)
    end
  end
end
