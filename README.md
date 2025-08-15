# RuleBook

A lightweight, deterministic forward-chaining rules engine for Elixir.

## Installation

Add to your mix deps:

```elixir
{:rule_book, "~> 0.1.0"}
```

## Quick start

```elixir
defmodule FraudRules do
  use RuleBook.DSL

  defmodule User do
    defstruct [:id, :country]
  end

  defmodule Payment do
    defstruct [:id, :user_id, :amount, :country]
  end

  defmodule Decision do
    defstruct [:payment_id, :status, :reason]
  end

  # Block payment when the user's country differs from the payment country
  defrule :block_if_country_mismatch,
    when: [
      %Payment{id: payment_id, user_id: uid, country: pay_country},
      %User{id: uid, country: user_country}
    ],
    then: fn ctx ->
      b = ctx.binding
      if b.pay_country != b.user_country do
        RuleBook.Action.assert(ctx, %Decision{
          payment_id: b.payment_id,
          status: :blocked,
          reason: :country_mismatch
        })
      else
        ctx
      end
    end,
    salience: 10
end

# 1) Get facts (user, payment)
user = %FraudRules.User{id: 1, country: :US}
payment = %FraudRules.Payment{id: 10, user_id: 1, amount: 125_00, country: :DE}

# 2) Run rules
{:ok, rb} = RuleBook.new(rules: FraudRules)
rb = rb |> RuleBook.assert(user) |> RuleBook.assert(payment)
{rb, _acts} = RuleBook.run(rb)

# 3) Decide: allow if no blocking decision, otherwise block
blocked? =
  RuleBook.facts(rb)
  |> Enum.any?(fn
    %FraudRules.Decision{payment_id: ^payment.id, status: :blocked} -> true
    _ -> false
  end)

case blocked? do
  true -> :block
  false -> :allow
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/rule_book>.
