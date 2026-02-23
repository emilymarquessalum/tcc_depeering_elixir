defmodule TccDepeeringElixir.BViewRangeLoaderTest do
  use ExUnit.Case
  doctest TccDepeeringElixir.BViewRangeLoader

  describe "generate_date_hour_pairs" do
    test "generates correct date/hour pairs with time_delta=8 from 2026-01-01 to 2026-01-03" do
      start_date = Date.from_iso8601!("2026-01-01")
      end_date = Date.from_iso8601!("2026-01-03")
      time_delta = 8

      result = TccDepeeringElixir.BViewRangeLoader.generate_date_hour_pairs(start_date, end_date, time_delta)

      expected = [
        {Date.from_iso8601!("2026-01-01"), 0},
        {Date.from_iso8601!("2026-01-01"), 8},
        {Date.from_iso8601!("2026-01-01"), 16},
        {Date.from_iso8601!("2026-01-02"), 0},
        {Date.from_iso8601!("2026-01-02"), 8},
        {Date.from_iso8601!("2026-01-02"), 16},
        {Date.from_iso8601!("2026-01-03"), 0},
        {Date.from_iso8601!("2026-01-03"), 8},
        {Date.from_iso8601!("2026-01-03"), 16}
      ]

      assert result == expected
    end

    test "generates correct date/hour pairs with time_delta=12 from 2026-01-01 to 2026-01-02" do
      start_date = Date.from_iso8601!("2026-01-01")
      end_date = Date.from_iso8601!("2026-01-02")
      time_delta = 12

      result = TccDepeeringElixir.BViewRangeLoader.generate_date_hour_pairs(start_date, end_date, time_delta)

      expected = [
        {Date.from_iso8601!("2026-01-01"), 0},
        {Date.from_iso8601!("2026-01-01"), 12},
        {Date.from_iso8601!("2026-01-02"), 0},
        {Date.from_iso8601!("2026-01-02"), 12}
      ]

      assert result == expected
    end

    test "generates correct date/hour pairs with time_delta=6 from 2026-01-01 to 2026-01-02" do
      start_date = Date.from_iso8601!("2026-01-01")
      end_date = Date.from_iso8601!("2026-01-02")
      time_delta = 6

      result = TccDepeeringElixir.BViewRangeLoader.generate_date_hour_pairs(start_date, end_date, time_delta)

      expected = [
        {Date.from_iso8601!("2026-01-01"), 0},
        {Date.from_iso8601!("2026-01-01"), 6},
        {Date.from_iso8601!("2026-01-01"), 12},
        {Date.from_iso8601!("2026-01-01"), 18},
        {Date.from_iso8601!("2026-01-02"), 0},
        {Date.from_iso8601!("2026-01-02"), 6},
        {Date.from_iso8601!("2026-01-02"), 12},
        {Date.from_iso8601!("2026-01-02"), 18}
      ]

      assert result == expected
    end

    test "handles single day correctly" do
      start_date = Date.from_iso8601!("2026-01-01")
      end_date = Date.from_iso8601!("2026-01-01")
      time_delta = 8

      result = TccDepeeringElixir.BViewRangeLoader.generate_date_hour_pairs(start_date, end_date, time_delta)

      expected = [
        {Date.from_iso8601!("2026-01-01"), 0},
        {Date.from_iso8601!("2026-01-01"), 8},
        {Date.from_iso8601!("2026-01-01"), 16}
      ]

      assert result == expected
    end
  end
end
