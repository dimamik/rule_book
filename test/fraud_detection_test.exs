defmodule RuleBook.FraudDetectionTest do
  use ExUnit.Case, async: true
  alias RuleBook.DSL
  alias RuleBook.Action

  defmodule FraudRules do
    use DSL

    defmodule User do
      defstruct [:id, :country]
    end

    defmodule Payment do
      defstruct [:id, :user_id, :amount, :country]
    end

    defmodule Decision do
      defstruct [:payment_id, :status, :reason]
    end

    defrule :block_if_country_mismatch,
      when: [
        %Payment{id: payment_id, user_id: uid, country: pay_country},
        %User{id: uid, country: user_country} when pay_country != user_country
      ],
      then: fn %{binding: context} ->
        Action.assert(context, %Decision{
          payment_id: context.payment_id,
          status: :blocked,
          reason: :country_mismatch
        })
      end,
      salience: 10
  end

  test "blocks payment when user and payment countries differ" do
    user = %FraudRules.User{id: 1, country: :US}
    payment = %FraudRules.Payment{id: 10, user_id: 1, amount: 125_00, country: :DE}

    {:ok, rb} = RuleBook.new(rules: FraudRules)
    rb = rb |> RuleBook.assert(user) |> RuleBook.assert(payment)
    {rb, acts} = RuleBook.run(rb)

    assert Enum.any?(acts, &(&1.rule == :block_if_country_mismatch))

    blocked? =
      RuleBook.facts(rb)
      |> Enum.any?(fn
        %FraudRules.Decision{payment_id: id, status: :blocked} -> id == payment.id
        _ -> false
      end)

    assert blocked?
  end

  test "allows payment when countries match" do
    user = %FraudRules.User{id: 1, country: :US}
    payment = %FraudRules.Payment{id: 11, user_id: 1, amount: 50_00, country: :US}

    {:ok, rb} = RuleBook.new(rules: FraudRules)
    rb = rb |> RuleBook.assert(user) |> RuleBook.assert(payment)
    {rb, _acts} = RuleBook.run(rb)

    blocked? =
      RuleBook.facts(rb)
      |> Enum.any?(fn
        %FraudRules.Decision{payment_id: id, status: :blocked} -> id == payment.id
        _ -> false
      end)

    refute blocked?
  end

  test "allows payment when countries differ for different users" do
    user = %FraudRules.User{id: 1, country: :US}
    payment = %FraudRules.Payment{id: 10, user_id: 2, amount: 125_00, country: :DE}

    {:ok, rb} = RuleBook.new(rules: FraudRules)
    rb = rb |> RuleBook.assert(user) |> RuleBook.assert(payment)
    {rb, _acts} = RuleBook.run(rb)

    blocked? =
      RuleBook.facts(rb)
      |> Enum.any?(fn
        %FraudRules.Decision{payment_id: id, status: :blocked} -> id == payment.id
        _ -> false
      end)

    refute blocked?
  end
end
