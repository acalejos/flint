defmodule FlintTest do
  use ExUnit.Case
  doctest Flint

  test "greets the world" do
    assert Flint.hello() == :world
  end
end
