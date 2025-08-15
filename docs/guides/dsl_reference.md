# DSL Reference

## defrule

Define a rule inside a module that `use`s `RuleBook.DSL`.

```
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
		salience: 10,
		once: true
end
```

### Patterns and Guards

- `when:` accepts a list of patterns. Each is matched against facts.
- You can use Elixir guards with `when` after any pattern. The guard is evaluated with the variables bound so far.
- Variables with the same name are unified across patterns. If later bindings conflict, the match fails.

Example with unification and a guard comparing values across facts:

```
defrule :country_mismatch,
	when: [
		%Payment{user_id: uid, country: pay_country},
		%User{id: uid, country: user_country} when pay_country != user_country
	],
	then: fn ctx -> ctx end
```

### Action

`then:` is a function `(ctx -> ctx | effects)` where `ctx` has:

- `:rb` — the RuleBook session
- `:binding` — map of variables bound by patterns
- `:effects` — accumulated effects

Use `RuleBook.Action` helpers like `emit/3`, `assert/2`, `retract/2`, `log/3` to return effects.

### Options

- `salience` — integer priority, higher first.
- `once` — when true, rule fires once per unique bindings set.
- `mode` — `:once` or `:per_fact` (defaults to `:per_fact`).
- `throttle` — `%{key: (bindings -> any), interval_ms: non_neg_integer}` experimental.
