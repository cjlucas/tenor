
defmodule Foo do
  import ExProf.Macro

  def run(fpath) do
    profile do
      AudioTag.Parser.parse!(fpath)
    end
  end
end
