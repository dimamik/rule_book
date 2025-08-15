defmodule RuleBook.AgendaConflictTest do
  use ExUnit.Case, async: true
  alias RuleBook.DSL

  defmodule Order do
    defstruct [:id, :total]
  end

  defmodule Rules do
    use DSL

    defrule :r1,
      when: [%Order{id: id, total: total} when total > 100],
      then: fn ctx -> ctx end,
      salience: 5

    defrule :r2,
      when: [%Order{id: id, total: total} when total > 100],
      then: fn ctx -> ctx end,
      salience: 10
  end

  test "higher salience first" do
    {:ok, rb} = RuleBook.new(rules: Rules)
    rb = RuleBook.assert(rb, %Order{id: 1, total: 200})
    acts = RuleBook.agenda(rb)
    assert [%{rule: :r2}, %{rule: :r1}] = acts
  end
end
