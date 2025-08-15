defmodule RuleBookSmokeTest do
  use ExUnit.Case, async: true

  test "new session" do
    {:ok, rb} = RuleBook.new()
    assert [] = Enum.to_list(RuleBook.facts(rb))
    assert [] = RuleBook.agenda(rb)
  end
end
