defmodule FileWatcher do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def add_dir(dir) do
    GenServer.cast(__MODULE__, {:add_dir, dir})
  end

  def init(:ok) do
    {:ok, nil}
  end

  def handle_cast({:add_dir, dir}, state) do
    {:ok, _} = AudioScanner.start_link(dir)
    {:noreply, state}
  end
end
