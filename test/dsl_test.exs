defmodule RuleBook.DSLTest do
  use ExUnit.Case, async: true

  alias RuleBook.Types

  defmodule Order do
    defstruct [:id, :total]
  end

  defmodule Rules do
    use RuleBook.Rules

    defrule :flag_large_order,
      when: [
        %Order{id: id, total: total} when total > 1000,
        %{user: %{status: :vip, id: user_id}}
      ],
      then: fn ctx -> ctx end,
      salience: 10,
      once: true
  end

  test "compiles rules into IR" do
    rules = Rules.__rulebook_rules__()
    assert [%Types.Rule{name: :flag_large_order, salience: 10, once: true} = r] = rules
    assert length(r.patterns) == 2
    assert is_function(hd(r.patterns).matcher, 1)
  end
end
