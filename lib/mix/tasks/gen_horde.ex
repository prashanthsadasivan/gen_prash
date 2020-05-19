defmodule Mix.Tasks.GenHorde do
  use Mix.Task

  def run(args) do
    module_name = case args do
      [module_name] -> validate_module_name(module_name)
      _ -> raise "Expected single argument that is a valid module name. got: #{inspect(args)}"
    end

    camel_case_name = Macro.underscore(module_name)
    dir = "lib/#{camel_case_name}/"
    File.mkdir_p!(dir)

    [
      {get_node_listener_template(), "#{dir}/node_listener.ex"},
      {get_registry_template(), "#{dir}/horde_registry.ex"},
      {get_supervisor_template(), "#{dir}/horde_supervisor.ex"}
    ]
    |> Enum.map(fn {template, file_name} -> File.write!(file_name, EEx.eval_string(template, module_name: module_name)) end)
    things_to_paste = 
      """
      children = [
        # ... other deps
        #{module_name}.DynSupervisor,
        #{module_name}.DynRegistry,
        #{module_name}.NodeListener,
      ]
      """

    IO.puts("Add the following to your supervision tree: \n#{things_to_paste}")
  end

  def validate_module_name(module_name) do
    case module_name =~ ~r/^[A-Z]\w*(\.[A-Z]\w*)*$/ do
      true -> module_name
      _ -> raise "Expected single argument that is a valid module name. got: #{inspect(module_name)}"
    end
  end

  def get_node_listener_template do
    """
    defmodule <%= module_name %>.NodeListener do
      use GenServer

      def start_link(), do: GenServer.start_link(__MODULE__, [])

      def init(_) do
        :net_kernel.monitor_nodes(true, node_type: :visible)
        {:ok, nil}
      end

      def handle_info({:nodeup, _node, _node_type}, state) do
        set_members(<%= module_name %>.DynRegistry)
        set_members(<%= module_name %>.DynSupervisor)
        {:noreply, state}
      end

      def handle_info({:nodedown, _node, _node_type}, state) do
        set_members(<%= module_name %>.DynRegistry)
        set_members(<%= module_name %>.DynSupervisor)
        {:noreply, state}
      end

      defp set_members(name) do
        members =
        [Node.self() | Node.list()]
        |> Enum.map(fn node -> {name, node} end)
        :ok = Horde.Cluster.set_members(name, members)
      end
    end
    """
  end

  def get_registry_template do
    """
    defmodule <%= module_name %>.DynRegistry do
      use Horde.Registry

      def start_link(init_arg, options \\\\ []) do
        Horde.Registry.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      def init(options) do
        [members: get_members(), keys: :unique]
        |> Keyword.merge(options)
        |> Horde.Registry.init()
      end

      defp get_members() do
        [Node.self() | Node.list()]
        |> Enum.map(fn node -> {<%= module_name %>.DynRegistry, node} end)
      end
    end
    """
  end

  def get_supervisor_template do
    """
    defmodule <%= module_name %>.DynSupervisor do
      use Horde.DynamicSupervisor

      def start_link(init_arg, options \\\\ []) do
        Horde.DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      def init(options) do
        [strategy: :one_for_one, members: get_members()]
        |> Keyword.merge(options)
        |> IO.inspect
        |> Horde.DynamicSupervisor.init()
      end

      defp get_members() do
        [Node.self() | Node.list()]
        |> Enum.map(fn node -> {<%= module_name %>.DynSupervisor, node} end)
      end
    end
    """
  end

end
