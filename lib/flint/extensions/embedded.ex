defmodule Flint.Extensions.Embedded do
  @moduledoc """
  An extension to house common default configurations for embedded schemas. These configurations are specific for
  in-memory schemas.

  ## Attributes

  The following attributes and defaults are set by this extension:

  * `:schema_prefix`
  * `:schema_context`
  * `:primary_key` - defaults to `false`
  * `:timestamp_opts` - defaults to `[type: :naive_datetime]`

  A new schema reflection function is made for each attribute:

  ```elixir
  __schema__(:schema_context)
  ...
  ```
  """
  use Flint.Extension

  attribute :schema_prefix
  attribute :schema_context
  attribute :primary_key, default: false
  attribute :timestamp_opts, default: [type: :naive_datetime]
end
