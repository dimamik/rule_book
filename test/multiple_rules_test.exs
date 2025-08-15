defmodule RuleBook.MultipleRulesTest do
  use ExUnit.Case, async: true

  defmodule Order do
    defstruct [:id, :total]
  end

  defmodule Rules do
    use RuleBook.Rules

    defrule :r_low,
      when: [%Order{id: id, total: total} when total >= 1],
      salience: 1,
      then: fn ctx -> ctx end

    defrule :r_mid,
      when: [%Order{id: id, total: total} when total >= 10],
      salience: 5,
      then: fn ctx -> ctx end

    defrule :r_high,
      when: [%Order{id: id, total: total} when total >= 100],
      salience: 10,
      then: fn ctx -> ctx end
  end

  test "multiple rules activate and are ordered by salience" do
    rb = RuleBook.new(rules: Rules)
    rb = RuleBook.assert(rb, %Order{id: 1, total: 150})
    acts = RuleBook.agenda(rb)
    assert [%{rule: :r_high}, %{rule: :r_mid}, %{rule: :r_low}] = Enum.map(acts, &%{rule: &1.rule})
  end

  test "rules fire independently across steps" do
    rb = RuleBook.new(rules: Rules)
    rb = RuleBook.assert(rb, %Order{id: 2, total: 50})

    {rb, act1} = RuleBook.step(rb)
    assert %{rule: :r_mid} = act1

    {rb, act2} = RuleBook.step(rb)
    assert %{rule: :r_low} = act2

    {_rb, act3} = RuleBook.step(rb)
    assert :none == act3
  end
end
