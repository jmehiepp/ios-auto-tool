#pragma once

// Starts MCP JSON-RPC HTTP server on the given port in a background thread.
// Bind address: 127.0.0.1 (localhost only — access via SSH tunnel)
void mcp_server_start(int port);
