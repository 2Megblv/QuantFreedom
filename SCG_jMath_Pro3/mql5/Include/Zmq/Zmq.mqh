// Simplified dummy ZMQ implementation for standard compilation capability
// In a real environment, you'd drop the libzmq.dll and standard dingmaotu/mql-zmq bindings here.

#define ZMQ_REP 4
#define ZMQ_PULL 7
#define ZMQ_PUSH 8
#define ZMQ_NOBLOCK 1

class Context {
public:
   Context(const string name) {}
   ~Context() {}
};

class Socket {
public:
   Socket(Context& ctx, int type) {}
   ~Socket() {}

   bool bind(const string endpoint) { return true; }
   bool connect(const string endpoint) { return true; }

   int send(const string msg, int flags=0) { return StringLen(msg); }
   int recv(string &msg, int flags=0) {
      // Dummy noblock receive
      return 0;
   }
};
