defmodule Ingest do
  def ingest do
    System.argv |> Enum.each(&AudioScanner.run/1)
  end  
end

#:observer.start
Ingest.ingest
