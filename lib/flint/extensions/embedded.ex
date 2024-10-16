defmodule Flint.Extensions.Embedded do
  @moduledoc """
  An extension to house common default configurations for embedded schemas. These configurations are specific for
  in-memory schemas.
  """
  use Flint.Extension

  attribute :schema_prefix
  attribute :schema_context
  attribute :primary_key, default: false
  attribute :timestamp_opts, default: [type: :naive_datetime]
end
