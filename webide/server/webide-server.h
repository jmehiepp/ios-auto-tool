#pragma once

// Starts the Web IDE HTTP server on the given port in a background thread.
// scripts_dir: path where Lua scripts are stored (e.g. /Library/IOSAutoTool/scripts)
// web_root:    path where frontend assets are installed (e.g. /Library/IOSAutoTool/webide)
void webide_server_start(int port, const char *scripts_dir, const char *web_root);

// Broadcast a log line to all connected WebSocket /ws/logs clients.
// Called from logger.m when a script is running.
void webide_ws_broadcast_log(const char *level, const char *message);
