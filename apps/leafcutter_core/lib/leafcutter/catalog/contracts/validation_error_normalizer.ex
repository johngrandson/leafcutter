defmodule Leafcutter.Catalog.Contracts.ValidationErrorNormalizer do
  @moduledoc false

  alias Leafcutter.Catalog.Contracts.ValidationError

  @doc false
  @spec normalize(JSV.ValidationError.t()) :: ValidationError.details()
  def normalize(%JSV.ValidationError{} = error) do
    %{"valid" => false, "details" => units} =
      JSV.normalize_error(error, sort: :asc, keys: :strings)

    %{
      "valid" => false,
      "details" => normalize_units(units)
    }
  end

  @spec normalize_units([map()]) :: [ValidationError.details()]
  defp normalize_units(units) do
    units
    |> Enum.map(&normalize_unit/1)
    |> Enum.sort_by(&unit_sort_key/1)
  end

  @spec normalize_unit(map()) :: ValidationError.details()
  defp normalize_unit(%{
         "valid" => valid,
         "instanceLocation" => instance_location,
         "evaluationPath" => evaluation_path,
         "schemaLocation" => schema_location
       } = unit)
       when is_boolean(valid) and is_binary(instance_location) and
              is_binary(evaluation_path) and is_binary(schema_location) do
    normalized = %{
      "valid" => valid,
      "instanceLocation" => instance_location,
      "evaluationPath" => evaluation_path,
      "schemaLocation" => schema_location
    }

    case Map.fetch(unit, "errors") do
      {:ok, errors} when is_list(errors) ->
        Map.put(normalized, "errors", normalize_keyword_errors(errors))

      :error ->
        normalized
    end
  end

  @spec normalize_keyword_errors([map()]) :: [ValidationError.details()]
  defp normalize_keyword_errors(errors) do
    errors
    |> Enum.map(&normalize_keyword_error/1)
    |> Enum.sort_by(fn error ->
      {Map.fetch!(error, "kind"), Map.get(error, "details", [])}
    end)
  end

  @spec normalize_keyword_error(map()) :: ValidationError.details()
  defp normalize_keyword_error(%{"kind" => kind, "details" => details})
       when is_binary(kind) and is_list(details) do
    %{
      "kind" => kind,
      "details" => normalize_units(details)
    }
  end

  defp normalize_keyword_error(%{"kind" => kind}) when is_binary(kind) do
    %{"kind" => kind}
  end

  @spec unit_sort_key(ValidationError.details()) :: tuple()
  defp unit_sort_key(unit) do
    {
      Map.fetch!(unit, "instanceLocation"),
      Map.fetch!(unit, "schemaLocation"),
      Map.fetch!(unit, "evaluationPath"),
      if(Map.fetch!(unit, "valid"), do: 1, else: 0),
      Map.get(unit, "errors", [])
    }
  end
end
