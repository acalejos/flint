defmodule Flint.Extension.Config do
  @moduledoc false
  use Spark.InfoGenerator, extension: Flint.Extension.Dsl, sections: [:attributes, :options]
end
