# RuleBook

A lightweight, deterministic forward-chaining rules engine for Elixir.

## Installation

Add to your mix deps:

```elixir
{:rule_book, "~> 0.1.0"}
```

## Quick start

```elixir
defmodule MyRules do
  use RuleBook.DSL

  defmodule Order do
    defstruct [:id, :total]
  end

  defrule :vip_large_order,
    when: [
      %Order{id: id, total: total} when total > 1000,
      %{user: %{status: :vip, id: user_id}}
    ],
    then: fn ctx -> ctx end,
    salience: 20,
    once: true
end

{:ok, rb} = RuleBook.new(rules: MyRules)
rb = rb |> RuleBook.assert(%MyRules.Order{id: 1, total: 1500}) |> RuleBook.assert(%{user: %{id: 7, status: :vip}})
{rb, activations} = RuleBook.run(rb)
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/rule_book>.
