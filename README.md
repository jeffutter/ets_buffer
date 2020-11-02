# ETSBuffer

<!-- MDOC !-->

ETSBuffer is a simple buffer that stores a maximum of N events, keeping only the N events with the greatest sort keys.

ETSBuffer is backed by an ordered set ETS table, and thus the buffer is ordered using erlang term ordering of the sort key to determine which events are the greatest.

ETSBuffer also uses a protected, read concurrent optimized ETS table so that the buffer can be read concurrently by many processes, but must be updated through a single process.

## Example

```elixir

iex(1)> buffer = ETSBuffer.init(max_size: 5)

iex(1)> ETSBuffer.push(buffer, 1, 1)
iex(2)> ETSBuffer.push(buffer, 2, 2)
iex(3)> ETSBuffer.push(buffer, 3, 3)
iex(4)> ETSBuffer.push(buffer, 0, 0)
iex(5)> ETSBuffer.push(buffer, 6, 6)
iex(6)> ETSBuffer.push(buffer, 5, 5)

iex(7)> ETSBuffer.list()
[2,3,4,5,6]
```
