defmodule RuleBook.InfiniteLoopRegressionTest do
  use ExUnit.Case, async: true

  defmodule Rules do
    use RuleBook.Rules

    defmodule A do
      defstruct [:id]
    end

    defmodule B do
      defstruct [:id]
    end

    # If effect application clears tokens, this rule can re-fire endlessly,
    # because asserting B does not change bindings of A but agenda is rebuilt
    # and the token that guards re-fire gets dropped. We prevent that.
    defrule :assert_b_when_a,
      when: [%A{id: id}],
      then: fn ctx ->
        ctx
        |> RuleBook.Action.assert(%B{id: ctx.binding.id})
        |> RuleBook.Action.emit(:fired, %{id: ctx.binding.id})
      end,
      salience: 0
  end

  test "run terminates and rule fires once" do
    rb = RuleBook.new(rules: Rules)
    rb = RuleBook.assert(rb, %Rules.A{id: 1})
    {rb, acts} = RuleBook.run(rb)
    # It should finish and produce exactly one activation fired
    assert length(acts) == 1
    assert [%{rule: :assert_b_when_a}] = acts

    # Memory should contain both facts
    assert Enum.any?(RuleBook.facts(rb), &match?(%Rules.A{id: 1}, &1))
    assert Enum.any?(RuleBook.facts(rb), &match?(%Rules.B{id: 1}, &1))
  end
end
