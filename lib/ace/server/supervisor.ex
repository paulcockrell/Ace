defmodule Ace.Server.Supervisor do
  @moduledoc """
  Supervise a collection of servers, that are listening or handling connections.

  Individual server processes can be stared from a supervisor,
  however recommended is to provide a constant sized number of accepting servers use a governor pool.
  """
  use Supervisor

  @doc """
  Start a new server supervisor.

  Each worker will be started with the same app defined behaviour.
  """
  @spec start_link(Ace.Server.app) :: {:ok, pid}
  def start_link(app) do
    case Supervisor.start_link(__MODULE__, app) do
      {:ok, pid} ->
        Process.put(__MODULE__, pid)
        {:ok, pid}
    end
  end

  ## MODULE CALLBACKS

  def init(app) do
    children = [
      worker(Ace.Server, [app], restart: :temporary)
    ]

    # Connections are temporary, if a server crashes we rely upon the client to make a new connection.
    supervise(children, strategy: :simple_one_for_one)
  end
end
