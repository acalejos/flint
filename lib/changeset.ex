defmodule Flint.Changeset do
  import Ecto.Changeset

  def apply_pre_transforms(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])
    all_pre_transforms = module.__schema__(:pre_transforms)

    for {field, pre_transforms} <- all_pre_transforms, reduce: changeset do
      changeset ->
        {derived_expression, _pre_transforms} = Keyword.pop(pre_transforms, :derive)
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

  def apply_post_transforms(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])
    all_post_transforms = module.__schema__(:post_transforms)

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

  def apply_validations(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    all_validations = module.__schema__(:validations)

    for {field, validations} <- all_validations, reduce: changeset do
      changeset ->
        {block, validations} = Keyword.pop(validations, :block, [])
        {when_condition, validations} = Keyword.pop(validations, :when)
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

        validation_args = [
          validate_inclusion: validate_inclusion_arg,
          validate_exclusion: validate_exclusion_arg,
          validate_number: validate_number_args,
          validate_length: validate_length_args,
          validate_format: validate_format_arg,
          validate_subset: validate_subset_arg
        ]

        changeset =
          Enum.reduce(validation_args, changeset, fn
            {_func, nil}, chngset ->
              chngset

            {_func, []}, chngset ->
              chngset

            {func, arg}, chngset ->
              apply(Ecto.Changeset, func, [chngset, field, arg])
          end)

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

        block
        |> Enum.with_index()
        |> Enum.reduce(changeset, fn
          {{quoted_condition, quoted_err}, index}, chngset ->
            try do
              {invalid?, _bindings} = Code.eval_quoted(quoted_condition, bindings, env)

              invalid? =
                if is_function(invalid?) do
                  case Function.info(invalid?, :arity) do
                    {:arity, 0} ->
                      apply(invalid?, [])

                    {:arity, 1} when not is_nil(field) ->
                      apply(invalid?, [fetch_change!(changeset, field)])

                    _ ->
                      raise ArgumentError,
                            "Anonymous functions in validation clause must be either 0-arity or an input value for the field must be provided."
                  end
                else
                  invalid?
                end

              {err_msg, _bindings} = Code.eval_quoted(quoted_err, bindings, env)

              if invalid? do
                add_error(chngset, field, err_msg,
                  validation: :block,
                  clause: index + 1
                )
              else
                chngset
              end
            rescue
              _ ->
                add_error(
                  chngset,
                  field,
                  "Error evaluating expression in Clause ##{index + 1} of `do:` block"
                )
            end
        end)
    end
  end

  def changeset(schema, params \\ %{}, bindings \\ []) do
    module = schema.__struct__
    fields = module.__schema__(:fields) |> MapSet.new()
    embedded_fields = module.__schema__(:embeds) |> MapSet.new()

    params =
      case params do
        %Ecto.Changeset{params: params} -> params
        s when is_struct(s) -> Map.from_struct(params)
        _ -> params
      end

    required = module.__schema__(:required)

    fields = fields |> MapSet.difference(embedded_fields)

    required_embeds = Enum.filter(required, &(&1 in embedded_fields))

    required_fields = Enum.filter(required, &(&1 in fields))

    changeset =
      schema
      |> cast(params, fields |> MapSet.to_list())

    changeset =
      for field <- embedded_fields, reduce: changeset do
        changeset ->
          changeset
          |> cast_embed(field,
            required: field in required_embeds,
            with: &changeset(&1, &2, bindings)
          )
      end

    changeset
    |> validate_required(required_fields)
    |> apply_pre_transforms(bindings)
    |> apply_validations(bindings)
    |> apply_post_transforms(bindings)
  end
end
