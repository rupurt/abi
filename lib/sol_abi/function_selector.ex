defmodule SolABI.FunctionSelector do
  @moduledoc """
  Module to help parse the SolABI function signatures, e.g.
  `my_function(uint64, string[])`.
  """

  require Integer

  @type type ::
          {:uint, integer()}
          | :bool
          | :bytes
          | :string
          | :address
          | {:array, type}
          | {:array, type, non_neg_integer}
          | {:tuple, [type]}

  @type t :: %__MODULE__{
          function: String.t(),
          types: [type],
          returns: type
        }

  defstruct [:function, :types, :returns]

  @doc """
  Decodes a function selector to a struct.

  ## Examples

      iex> SolABI.FunctionSelector.decode("bark(uint256,bool)")
      %SolABI.FunctionSelector{
        function: "bark",
        types: [
          {:uint, 256},
          :bool
        ]
      }

      iex> SolABI.FunctionSelector.decode("(uint256,bool)")
      %SolABI.FunctionSelector{
        function: nil,
        types: [
          {:uint, 256},
          :bool
        ]
      }

      iex> SolABI.FunctionSelector.decode("growl(uint,address,string[])")
      %SolABI.FunctionSelector{
        function: "growl",
        types: [
          {:uint, 256},
          :address,
          {:array, :string}
        ]
      }

      iex> SolABI.FunctionSelector.decode("rollover()")
      %SolABI.FunctionSelector{
        function: "rollover",
        types: []
      }

      iex> SolABI.FunctionSelector.decode("do_playDead3()")
      %SolABI.FunctionSelector{
        function: "do_playDead3",
        types: []
      }

      iex> SolABI.FunctionSelector.decode("pet(address[])")
      %SolABI.FunctionSelector{
        function: "pet",
        types: [
          {:array, :address}
        ]
      }

      iex> SolABI.FunctionSelector.decode("paw(string[2])")
      %SolABI.FunctionSelector{
        function: "paw",
        types: [
          {:array, :string, 2}
        ]
      }

      iex> SolABI.FunctionSelector.decode("scram(uint256[])")
      %SolABI.FunctionSelector{
        function: "scram",
        types: [
          {:array, {:uint, 256}}
        ]
      }

      iex> SolABI.FunctionSelector.decode("shake((string))")
      %SolABI.FunctionSelector{
        function: "shake",
        types: [
          {:tuple, [:string]}
        ]
      }
  """
  def decode(signature) do
    SolABI.Parser.parse!(signature, as: :selector)
  end

  @doc """
  Decodes the given type-string as a simple array of types.

  ## Examples

      iex> SolABI.FunctionSelector.decode_raw("string,uint256")
      [:string, {:uint, 256}]

      iex> SolABI.FunctionSelector.decode_raw("")
      []
  """
  def decode_raw(type_string) do
    {:tuple, types} = decode_type("(#{type_string})")
    types
  end

  @doc false
  def parse_specification_item(%{"type" => "function"} = item) do
    %{
      "name" => function_name,
      "inputs" => named_inputs,
      "outputs" => named_outputs
    } = item

    input_types = Enum.map(named_inputs, &parse_specification_type/1)
    output_types = Enum.map(named_outputs, &parse_specification_type/1)

    %SolABI.FunctionSelector{
      function: function_name,
      types: input_types,
      returns: List.first(output_types)
    }
  end

  def parse_specification_item(%{"type" => "fallback"}) do
    %SolABI.FunctionSelector{
      function: nil,
      types: [],
      returns: nil
    }
  end

  def parse_specification_item(_), do: nil

  defp parse_specification_type(%{"type" => type}), do: decode_type(type)

  @doc """
  Decodes the given type-string as a single type.

  ## Examples

      iex> SolABI.FunctionSelector.decode_type("uint256")
      {:uint, 256}

      iex> SolABI.FunctionSelector.decode_type("(bool,address)")
      {:tuple, [:bool, :address]}

      iex> SolABI.FunctionSelector.decode_type("address[][3]")
      {:array, {:array, :address}, 3}
  """
  def decode_type(single_type) do
    SolABI.Parser.parse!(single_type, as: :type)
  end

  @doc """
  Encodes a function call signature.

  ## Examples

      iex> SolABI.FunctionSelector.encode(%SolABI.FunctionSelector{
      ...>   function: "bark",
      ...>   types: [
      ...>     {:uint, 256},
      ...>     :bool,
      ...>     {:array, :string},
      ...>     {:array, :string, 3},
      ...>     {:tuple, [{:uint, 256}, :bool]}
      ...>   ]
      ...> })
      "bark(uint256,bool,string[],string[3],(uint256,bool))"
  """
  def encode(function_selector) do
    types = get_types(function_selector) |> Enum.join(",")

    "#{function_selector.function}(#{types})"
  end

  defp get_types(function_selector) do
    for type <- function_selector.types do
      get_type(type)
    end
  end

  defp get_type(nil), do: nil
  defp get_type({:int, size}), do: "int#{size}"
  defp get_type({:uint, size}), do: "uint#{size}"
  defp get_type(:address), do: "address"
  defp get_type(:bool), do: "bool"
  defp get_type({:fixed, element_count, precision}), do: "fixed#{element_count}x#{precision}"
  defp get_type({:ufixed, element_count, precision}), do: "ufixed#{element_count}x#{precision}"
  defp get_type({:bytes, size}), do: "bytes#{size}"
  defp get_type(:function), do: "function"

  defp get_type({:array, type, element_count}), do: "#{get_type(type)}[#{element_count}]"

  defp get_type(:bytes), do: "bytes"
  defp get_type(:string), do: "string"
  defp get_type({:array, type}), do: "#{get_type(type)}[]"

  defp get_type({:tuple, types}) do
    encoded_types = Enum.map(types, &get_type/1)
    "(#{Enum.join(encoded_types, ",")})"
  end

  defp get_type(els), do: raise("Unsupported type: #{inspect(els)}")

  @doc false
  @spec is_dynamic?(SolABI.FunctionSelector.type()) :: boolean
  def is_dynamic?(:bytes), do: true
  def is_dynamic?(:string), do: true
  def is_dynamic?({:array, _type}), do: true
  def is_dynamic?({:array, type, len}) when len > 0, do: is_dynamic?(type)
  def is_dynamic?({:tuple, types}), do: Enum.any?(types, &is_dynamic?/1)
  def is_dynamic?(_), do: false
end
