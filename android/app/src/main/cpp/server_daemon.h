/**
 * server_daemon.h
 *
 * HTTP daemon interface for the Kingdom AI Server.
 */
#ifndef SERVER_DAEMON_H
#define SERVER_DAEMON_H

#include "kingdom_orchestrator.h"

namespace kingdom {

class ServerDaemon {
public:
    static void start(KingdomEngineHandle engine, int port = 8080);
    static void stop();
    static bool isRunning();
    static int  port();
};

} // namespace kingdom

#endif /* SERVER_DAEMON_H */
