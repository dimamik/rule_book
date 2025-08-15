defmodule RuleBook.ActionsTest do
  use ExUnit.Case, async: true
  alias RuleBook.DSL
  import RuleBook.Action

  defmodule Order do
    defstruct [:id, :total]
  end

  defmodule Rules do
    use DSL

    defrule :emit_on_large,
      when: [%Order{id: id, total: total} when total > 1000],
      then: fn ctx -> ctx |> emit(:notify, %{id: ctx.binding.id}) end
  end

  test "action emit returns effect" do
    {:ok, rb} = RuleBook.new(rules: Rules)
    rb = RuleBook.assert(rb, %Order{id: 1, total: 2000})
    {rb, act} = RuleBook.step(rb)
    assert %{rule: :emit_on_large} = act
    # No side-effect sink, but we expect step to return the activation and leave rb consistent
    assert is_list(RuleBook.agenda(rb))
  end
end
