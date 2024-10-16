defmodule Flint.Extension.Dsl do
  @moduledoc false
  @common_schema [
    name: [
      type: :atom,
      required: true,
      doc: "The name as an atom."
    ],
    default: [
      type: :any,
      required: false,
      doc: "The default value. `nil` by default."
    ],
    required: [
      type: :boolean,
      default: false,
      doc:
        "Whether the field is required. If it is required and not provided there will be a compile time error thrown."
    ],
    validator: [
      type: {:fun, [:any], :boolean},
      required: false,
      doc:
        "An arity-1 function that accepts the value of the option / attribute and returns whether it is valid. By convention, this is also used to enforce type adherance."
    ]
  ]
  @option %Spark.Dsl.Entity{
    name: :option,
    target: Flint.Extension.Field,
    args: [:name],
    schema: @common_schema
  }
  @options %Spark.Dsl.Section{
    name: :options,
    entities: [@option],
    top_level?: true
  }
  @attribute %Spark.Dsl.Entity{
    name: :attribute,
    target: Flint.Extension.Field,
    args: [:name],
    schema: @common_schema
  }
  @attributes %Spark.Dsl.Section{
    name: :attributes,
    entities: [@attribute],
    top_level?: true
  }
  use Spark.Dsl.Extension, sections: [@attributes, @options]
end
