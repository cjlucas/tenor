
defmodule Foo do
  import ExProf.Macro

  def run(fpath) do
    profile do
      AudioTag.MP3.parse(fpath)
    end
  end
end
