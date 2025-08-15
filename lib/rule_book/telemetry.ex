defmodule RuleBook.Telemetry do
  @moduledoc false
  # Minimal wrapper to avoid mandatory telemetry dependency in user apps
  def exec(event, measurements \\ %{}, metadata \\ %{}) do
    if Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :execute, 3) do
      :telemetry.execute(List.wrap(event), measurements, metadata)
    else
      :ok
    end
  end
end
