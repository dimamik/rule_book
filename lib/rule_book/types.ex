defmodule RuleBook.Types do
  @moduledoc false

  defmodule Rule do
    @moduledoc "Internal representation of a rule."
    defstruct [
      :name,
      # [Pattern.t()]
      :patterns,
      # function or MFA
      :action,
      salience: 0,
      once: false,
      # :once | :per_fact
      mode: :per_fact,
      # %{key: (bindings -> any), interval_ms: non_neg_integer}
      throttle: nil
    ]

    @type t :: %__MODULE__{
            name: atom(),
            patterns: [RuleBook.Types.Pattern.t()],
            action: (map() -> any()) | {module(), atom(), list()},
            salience: integer(),
            once: boolean(),
            mode: :once | :per_fact,
            throttle: nil | %{key: (map() -> any()), interval_ms: non_neg_integer()}
          }
  end

  defmodule Pattern do
    @moduledoc "Pattern with optional guard and extractor for bindings."
    defstruct [:matcher, :guard]

    @type t :: %__MODULE__{
            matcher: (term() -> {:ok, map()} | :nomatch),
            # guard receives the merged bindings so far and must return a boolean
            guard: nil | (map() -> boolean())
          }
  end
end
