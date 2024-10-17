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
  * `:when` - Let's you define an arbitrary boolean condition on the field which can refer to any `field` defined above it or itself. **NOTE** The `:when` option will output a generic error on failure, so if verbosity is desired, an [advanced validation](#advanced-validations) is more appropriate.

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
  def apply_validations(changeset, bindings \\ []) do
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
            {k, args} when is_list(args) ->
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

  defmacro __using__(_opts) do
    quote do
      def changeset(schema, params \\ %{}, bindings \\ []) do
        changeset =
          super(schema, params, bindings)

        Flint.Extensions.EctoValidations.apply_validations(changeset, bindings)
      end

      defoverridable changeset: 1,
                     changeset: 2,
                     changeset: 3
    end
  end
end
