defmodule BinTest do

  def one(<<>>) do
    nil
  end
  def one(bin) do
    <<_::8, rest::binary>> = bin
    one(rest)
  end
end
