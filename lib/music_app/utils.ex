defmodule MusicApp.Utils do

  @id3_timetamp_res [
    ~r/
      (?<year>(1[89][0-9]{2}|2[0-9]{3}))\-
      (?<month>(0[1-9]|1[12]))\-
      (?<day>([0123][0-9]))T
      (?<hour>([01][0-9]|2[0123])):
      (?<minute>[0-5][0-9]):
      (?<second>[0-5][0-9])/x,
    ~r/
      (?<year>(1[89][0-9]{2}|2[0-9]{3}))\-
      (?<month>(0[1-9]|1[12]))\-
      (?<day>([0123][0-9]))T
      (?<hour>([01][0-9]|2[0123])):
      (?<minute>[0-5][0-9])/x,
    ~r/
      (?<year>(1[89][0-9]{2}|2[0-9]{3}))\-
      (?<month>(0[1-9]|1[12]))\-
      (?<day>([0123][0-9]))T
      (?<hour>([01][0-9]|2[0123]))/x,
    ~r/
      (?<year>(1[89][0-9]{2}|2[0-9]{3}))\-
      (?<month>(0[1-9]|1[12]))\-
      (?<day>([0123][0-9]))/x,
    ~r/
      (?<year>(1[89][0-9]{2}|2[0-9]{3}))\-
      (?<month>(0[1-9]|1[12]))/x,
    ~r/(?<year>(1[89][0-9]{2}|2[0-9]{3}))/x,
    ]

  @default_capture %{
    "year" => 0,
    "month" => 1,
    "day" => 1,
    "hour" => 0,
    "minute" => 0,
    "second" => 0,
  }

  def parse_id3_timestamp(ts) do
    @id3_timetamp_res
    |> Enum.map(&Regex.named_captures(&1, ts))
    |> Enum.drop_while(&is_nil/1)
    |> List.first
    |> to_datetime
  end
  
  defp to_datetime(nil), do: nil
  defp to_datetime(ts) do
    capture = 
      ts
      |> Enum.map(fn {k, v} -> {k, String.to_integer(v)} end)
      |> Enum.into(%{})

    @default_capture
    |> Map.merge(capture)
    |> capture_to_datetime
  end

  defp capture_to_datetime(%{"year" => y, "month" => m, "day" => d, "hour" => h, "minute" => mi, "second" => s}) do
    NaiveDateTime.from_erl!({{y, m, d}, {h, mi, s}})
  end

  def binary_to_hex(bin) when is_binary(bin) do
    use Bitwise

    bin
    |> :binary.bin_to_list
    |> Enum.map(fn byte -> 
      [(byte &&& 0xF0) >>> 4, byte &&& 0xF]
    end)
    |> List.flatten
    |> Enum.map(&to_hex/1)
    |> :binary.list_to_bin
  end

  defp to_hex(0), do: "0"
  defp to_hex(1), do: "1"
  defp to_hex(2), do: "2"
  defp to_hex(3), do: "3"
  defp to_hex(4), do: "4"
  defp to_hex(5), do: "5"
  defp to_hex(6), do: "6"
  defp to_hex(7), do: "7"
  defp to_hex(8), do: "8"
  defp to_hex(9), do: "9"
  defp to_hex(10), do: "a"
  defp to_hex(11), do: "b"
  defp to_hex(12), do: "c"
  defp to_hex(13), do: "d"
  defp to_hex(14), do: "e"
  defp to_hex(15), do: "f"
end
