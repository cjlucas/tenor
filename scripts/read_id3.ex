System.argv
|> Enum.each(fn fname ->
  IO.puts fname

  File.read!(fname)
  |> AudioTag.ID3v2.read
  |> Enum.map(&AudioTag.ID3v2.Frame.parse_frame/1)
  |> Enum.map(&inspect/1)
  |> Enum.join("\n")
  |> IO.puts

  IO.puts ""
end)
