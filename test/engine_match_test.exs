defmodule RuleBook.EngineMatchTest do
  use ExUnit.Case, async: true

  defmodule Order do
    defstruct [:id, :total]
  end

  defmodule Rules do
    use RuleBook.Rules

    defrule :vip_large_order,
      when: [
        %Order{id: id, total: total} when total > 1000,
        %{user: %{status: :vip, id: user_id}}
      ],
      then: fn ctx -> ctx end,
      salience: 20,
      once: true
  end

  test "agenda contains activation when facts match" do
    rb = RuleBook.new(rules: Rules)

    rb =
      rb
      |> RuleBook.assert(%Order{id: 1, total: 1500})
      |> RuleBook.assert(%{user: %{id: 7, status: :vip}})

    acts = RuleBook.agenda(rb)
    assert [%{rule: :vip_large_order, salience: 20}] = acts
    [act] = acts
    assert %{id: 1, user_id: 7, total: 1500} = act.bindings
  end
end
