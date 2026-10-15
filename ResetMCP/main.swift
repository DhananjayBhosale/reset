import Foundation

// A minimal MCP server over stdio (newline-delimited JSON-RPC 2.0). It lets Claude Code ask Reset how much
// of the usage window is left, and set a pacing budget for a task, so an agent can pace itself. It only reads
// the snapshot Reset writes and keeps the budget in budget.json beside it; it never touches credentials or
// the network. The request handling lives in Reset/MCP/MCPServer.swift so it can be unit-tested.

setvbuf(stdout, nil, _IOLBF, 0)

let env = MCPServer.Environment()
while let line = readLine(strippingNewline: true) {
    if let reply = MCPServer.handle(line: line, env: env) { print(reply) }
}
