

defmodule TccDepeeringElixirWeb.BViewOscillationController do
  use TccDepeeringElixirWeb, :controller

  

  alias TccDepeeringElixir.VariabilityCalculator
  alias TccDepeeringElixir.IXPContext

  @doc """
  Calculate and save variability records for all configured IXPs.
  
  Loads all IXP configurations from data/configs/*.json,
  calculates variability metrics for the last 30 days,
  and stores both daily history and average variability data.
  
  Query parameters:
    - ip_version: 4 or 6 (default: 4)
    - snapshot_delta: hours between snapshots, typically 8 or 24 (default: 24)

  def create_variability_record(conn, params) do
    ip_version = 
      Map.get(params, "ip_version", "v4")  

    snapshot_delta = 
      Map.get(params, "snapshot_delta", "24") 
      |> parse_int(24)

    opts = [
      ip_version: ip_version,
      snapshot_delta: snapshot_delta,
      metric_version: 1
    ]

    case VariabilityCalculator.calculate_all_ixps_variability(opts) do
      {:ok, %{successful: successful, failed: failed}} ->
        # Calculate rankings after all IXPs are processed
        today = Date.utc_today()
        start_date = Date.add(today, -29)
        
        VariabilityCalculator.calculate_rankings(ip_version, start_date, today)

        successful_count = length(successful)
        failed_count = length(failed)

        json(conn, %{
          status: "success",
          message: "Variability calculation completed",
          summary: %{
            successful: successful_count,
            failed: failed_count,
            ip_version: ip_version,
            snapshot_delta: snapshot_delta,
            date_range: %{
              start: Date.to_string(start_date),
              end: Date.to_string(today)
            }
          },
          results: %{
            successful: 
              successful
              |> Enum.map(fn {:ok, result} ->
                %{
                  ixp: result.average_record.ixp_name,
                  daily_records: length(result.daily_records),
                  average_variability: result.average_record.variability_value
                }
              end),
            failed:
              failed
              |> Enum.map(fn {:error, reason} ->
                reason
              end)
          }
        })

      {:error, reason} ->
        json(conn, %{
          status: "error",
          message: "Failed to calculate variability",
          error: inspect(reason)
        })
    end
  end
  """
  @doc """
  Get variability records for a specific IXP.
  
  Query parameters:
    - ixp_id: ID of the IXP (required)
    - ip_version: 4 or 6 (default: 4)
    - limit: Number of records to return (default: 30)
  """
    """
  def get_ixp_variability(conn, params) do
    case Map.get(params, "ixp_id") do
      nil ->
        json(conn, %{
          status: "error",
          message: "ixp_id parameter is required"
        })

      ixp_id ->
        ip_version = 
          Map.get(params, "ip_version", "v4") 

        case IXPContext.get_ixp(ixp_id) do
          nil ->
            json(conn, %{
              status: "error",
              message: "IXP not found"
            })

          ixp ->
            histories = 
              TccDepeeringElixir.Repo.all(
                from h in TccDepeeringElixir.VariabilityHistory,
                where: h.ixp_id == ^ixp.id and h.ip_version == ^ip_version,
                order_by: [desc: h.variability_date],
                limit: 30
              )

            average =
              TccDepeeringElixir.Repo.one(
                from a in TccDepeeringElixir.AverageVariability,
                where: a.ixp_id == ^ixp.id and a.ip_version == ^ip_version,
                order_by: [desc: a.variability_end_date],
                limit: 1
              )

            json(conn, %{
              status: "success",
              ixp: %{
                id: ixp.id,
                name: ixp.name,
                rrc: ixp.rrc
              },
              ip_version: ip_version,
              history: histories,
              average: average
            })
        end
    end
  end
    """
    """
  # Private functions

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_int(int, _default) when is_integer(int), do: int
  defp parse_int(_, default), do: default
    """
end