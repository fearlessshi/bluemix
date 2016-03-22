// multisocks, copyright (c) 2013 coolypf

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <map>
#include <vector>
#include <Poco/Thread.h>
#include <Poco/Event.h>
#include <Poco/ErrorHandler.h>
#include <Poco/FIFOBuffer.h>
#include <Poco/Net/StreamSocket.h>
#include <Poco/Net/ServerSocket.h>

using namespace std;
using namespace Poco;
using namespace Poco::Net;

class error_handler : public ErrorHandler
{
public:
    virtual void exception(const Exception& exc)
    {
        printf("[!] Thread %u: Caught exception: %s\n", (unsigned int)Thread::currentTid(), exc.displayText().c_str());
        fflush(stdout);
        exit(1);
    }

    virtual void exception(const std::exception& exc)
    {
        printf("[!] Thread %u: Caught exception: %s\n", (unsigned int)Thread::currentTid(), exc.what());
        fflush(stdout);
        exit(2);
    }

    virtual void exception()
    {
        printf("[!] Thread %u: Caught unknown exception\n", (unsigned int)Thread::currentTid());
        fflush(stdout);
        exit(3);
    }
};

class
{
    map<string, string> config;
    string empty;

    int read_file(const char *filename, vector<char> &out)
    {
        FILE *fp = fopen(filename, "rb");
        if (!fp)
        {
            printf("[!] Fail to load: %s\n", filename);
            return 1;
        }
        char buf[4096];
        size_t sz;
        while ((sz = fread(buf, 1, 4096, fp)))
            out.insert(out.end(), buf, buf + sz);
        fclose(fp);
        for (size_t i = 0; i < out.size(); ++i)
            if (!out[i])
                out[i] = ' ';
        return 0;
    }

    void split_lines(const vector<char> &in, vector<string> &out)
    {
        size_t pos = 0;
        for (size_t i = 0; i < in.size(); ++i)
        {
            if (in[i] != '\r' && in[i] != '\n')
                continue;
            out.push_back(string(in.begin() + pos, in.begin() + i));
            if (in[i] == '\r' && i + 1 < in.size() && in[i + 1] == '\n')
                i++;
            pos = i + 1;
        }
        if (pos < in.size())
            out.push_back(string(in.begin() + pos, in.end()));
    }

    void trim_string(string &str)
    {
        const char *spaces = " \r\n\t\xb\xc";
        int first = 0, last = (int)str.size() - 1;
        while (first <= last && strchr(spaces, str[first]))
            ++first;
        while (last >= first && strchr(spaces, str[last]))
            --last;
        str.resize(last + 1);
        str.erase(0, first);
    }

    void split_string(const string &in, vector<string> &out, const char *delims)
    {
        size_t pos = 0;
        for (size_t i = 0; i < in.size(); ++i)
        {
            if (!strchr(delims, in[i]))
                continue;
            string part(in.begin() + pos, in.begin() + i);
            trim_string(part);
            out.push_back(part);
            pos = i + 1;
        }
        {
            string part(in.begin() + pos, in.end());
            trim_string(part);
            out.push_back(part);
        }
    }

public:
    int load(const char *filename)
    {
        vector<char> content;
        if (read_file(filename, content))
            return 1;
        vector<string> lines;
        split_lines(content, lines);
        for (size_t i = 0; i < lines.size(); ++i)
        {
            if (lines[i].empty() || lines[i][0] == '#')
                continue;
            vector<string> parts;
            split_string(lines[i], parts, "=");
            if (parts.size() != 2 || parts[0].empty())
            {
                printf("[!] Invalid config: %s (%d)\n", filename, (int)i + 1);
                continue;
            }
            if (config.find(parts[0]) != config.end())
                printf("[!] Override config: %s (%d)\n", filename, (int)i + 1);
            config[parts[0]] = parts[1];
        }
        return 0;
    }

    int i(const char *key) const
    {
        map<string, string>::const_iterator iter = config.find(string(key));
        if (iter == config.end())
        {
            printf("[!] No config: %s\n", key);
            return 0;
        }
        int ret = 0;
        if (sscanf(iter->second.c_str(), "%d", &ret) != 1)
            printf("[!] Invalid int: %s\n", key);
        return ret;
    }

    const string & s(const char *key) const
    {
        map<string, string>::const_iterator iter = config.find(string(key));
        if (iter == config.end())
        {
            printf("[!] No config: %s\n", key);
            return empty;
        }
        return iter->second;
    }
} config;

// Read from out buffer and send to remote
class reader : public Runnable
{
    int index;
    StreamSocket socket;
    Event &readable, &writable;
    FIFOBuffer &buffer;
    bool &self_stopped, &peer_stopped;
public:
    reader(int i, StreamSocket s, Event &r, Event &w, FIFOBuffer &b, bool &self, bool &peer)
        : index(i), socket(s), readable(r), writable(w), buffer(b), self_stopped(self), peer_stopped(peer)
    {
    }

    virtual void run()
    {
        printf("[.] Reader %d, tid = %u\n", index, (unsigned int)Thread::currentTid());
        fflush(stdout);
        char buf[8192];
        bool closed = false;
        while (true)
        {
            if (buffer.isReadable())
            {
                int sz = (int)buffer.read(buf, 8192);
                writable.set();
                int sent = 0;
                while (sent < sz)
                {
                    int sz2;
                    try
                    {
                        sz2 = socket.sendBytes(buf + sent, sz - sent);
                    }
                    catch (Exception &exc)
                    {
                        printf("[!] Reader %d: %s\n", index, exc.displayText().c_str());
                        fflush(stdout);
                        sz2 = 0;
                    }
                    if (sz2 <= 0)
                    {
                        closed = true;
                        break;
                    }
                    sent += sz2;
                }
                if (closed)
                    break;
            }
            else
            {
                if (peer_stopped)
                    break;
                readable.wait();
            }
        }
        try { socket.shutdownSend(); } catch (...) {}
        self_stopped = true;
        writable.set();
    }
};

// Receive from remote and write to in buffer
class writer : public Runnable
{
    int index;
    StreamSocket socket;
    Event &readable, &writable;
    FIFOBuffer &buffer;
    bool &self_stopped, &peer_stopped;
public:
    writer(int i, StreamSocket s, Event &r, Event &w, FIFOBuffer &b, bool &self, bool &peer)
        : index(i), socket(s), readable(r), writable(w), buffer(b), self_stopped(self), peer_stopped(peer)
    {
    }

    virtual void run()
    {
        printf("[.] Writer %d, tid = %u\n", index, (unsigned int)Thread::currentTid());
        fflush(stdout);
        char buf[8192];
        while (true)
        {
            int sz;
            try
            {
                sz = socket.receiveBytes(buf, 8192);
            }
            catch (Exception &exc)
            {
                printf("[!] Writer %d: %s\n", index, exc.displayText().c_str());
                fflush(stdout);
                sz = 0;
            }
            if (sz <= 0)
                break;
            int written = 0;
            while (written < sz)
            {
                if (buffer.isWritable())
                {
                    written += buffer.write(buf + written, sz - written);
                    readable.set();
                }
                else
                {
                    if (peer_stopped)
                        break;
                    writable.wait();
                }
            }
            if (peer_stopped)
                break;
        }
        try { socket.shutdownReceive(); } catch (...) {}
        self_stopped = true;
        readable.set();
    }
};

// Receive from local and write to out buffers
class divider : public Runnable
{
    int nr_conn;
    StreamSocket socket;
    vector<Event *> &readables;
    Event &writable;
    vector<FIFOBuffer *> buffers;
    bool &self_stopped, *peers_stopped;
public:
    divider(int n, StreamSocket s, vector<Event *> &vr, Event &w, vector<FIFOBuffer *> &b, bool &self, bool *peers)
        : nr_conn(n), socket(s), readables(vr), writable(w), buffers(b), self_stopped(self), peers_stopped(peers)
    {
    }

    virtual void run()
    {
        printf("[.] Divider, tid = %u\n", (unsigned int)Thread::currentTid());
        fflush(stdout);
        int sz0 = 8192 * nr_conn;
        char *buf0 = new char[sz0];
        char **bufv = new char *[nr_conn];
        for (int i = 0; i < nr_conn; ++i)
            bufv[i] = new char[8192];
        int *szv = new int[nr_conn];
        int *writtenv = new int[nr_conn];
        long long total = 0;
        bool peer_stopped = false;
        while (true)
        {
            int sz;
            try
            {
                sz = socket.receiveBytes(buf0, sz0);
            }
            catch (Exception &exc)
            {
                printf("[!] Divider: %s\n", exc.displayText().c_str());
                fflush(stdout);
                sz = 0;
            }
            if (sz <= 0)
                break;
            for (int i = 0; i < nr_conn; ++i)
            {
                szv[i] = 0;
                writtenv[i] = 0;
            }
            for (int i = 0; i < sz; ++i)
                bufv[(total + i) % nr_conn][szv[(total + i) % nr_conn]++] = buf0[i];
            total += sz;
            while (true)
            {
                bool done = true;
                for (int i = 0; i < nr_conn; ++i)
                    if (writtenv[i] < szv[i])
                        done = false;
                if (done)
                    break;
                bool written = false;
                for (int i = 0; i < nr_conn; ++i)
                {
                    if (buffers[i]->isWritable())
                    {
                        writtenv[i] += buffers[i]->write(bufv[i] + writtenv[i], szv[i] - writtenv[i]);
                        readables[i]->set();
                        written = true;
                    }
                }
                if (!written)
                {
                    for (int i = 0; i < nr_conn; ++i)
                        if (peers_stopped[i])
                            peer_stopped = true;
                    if (peer_stopped)
                        break;
                    writable.wait();
                    writable.reset();
                }
                if (peer_stopped)
                    break;
            }
        }
        try { socket.shutdownReceive(); } catch (...) {}
        self_stopped = true;
        for (int i = 0; i < nr_conn; ++i)
            readables[i]->set();
    }
};

// Read from in buffers and send to local
class combiner : public Runnable
{
    int nr_conn;
    StreamSocket socket;
    Event &readable;
    vector<Event *> &writables;
    vector<FIFOBuffer *> buffers;
    bool &self_stopped, *peers_stopped;
public:
    combiner(int n, StreamSocket s, Event &r, vector<Event *> &vw, vector<FIFOBuffer *> &b, bool &self, bool *peers)
        : nr_conn(n), socket(s), readable(r), writables(vw), buffers(b), self_stopped(self), peers_stopped(peers)
    {
    }

    virtual void run()
    {
        printf("[.] Combiner, tid = %u\n", (unsigned int)Thread::currentTid());
        fflush(stdout);
        char *buf0 = new char[8192 * nr_conn];
        char **bufv = new char *[nr_conn];
        for (int i = 0; i < nr_conn; ++i)
            bufv[i] = new char[8192];
        int *szv = new int[nr_conn];
        int *readv = new int[nr_conn];
        long long total = 0;
        bool peer_stopped = false, closed = false;
        while (true)
        {
            for (int i = 0; i < nr_conn; ++i)
            {
                szv[i] = buffers[i]->peek(bufv[i], 8192);
                readv[i] = 0;
            }
            int sz = 0;
            while (true)
            {
                int i = (total + sz) % nr_conn;
                if (readv[i] >= szv[i])
                    break;
                buf0[sz++] = bufv[i][readv[i]++];
            }
            total += sz;
            if (sz > 0)
            {
                for (int i = 0; i < nr_conn; ++i)
                {
                    if (readv[i] > 0)
                    {
                        buffers[i]->read(bufv[i], readv[i]);
                        writables[i]->set();
                    }
                }
                int sent = 0;
                while (sent < sz)
                {
                    int sz1;
                    try
                    {
                        sz1 = socket.sendBytes(buf0 + sent, sz - sent);
                    }
                    catch (Exception &exc)
                    {
                        printf("[!] Combiner: %s\n", exc.displayText().c_str());
                        fflush(stdout);
                        sz1 = 0;
                    }
                    if (sz1 <= 0)
                    {
                        closed = true;
                        break;
                    }
                    sent += sz1;
                }
                if (closed)
                    break;
            }
            else
            {
                for (int i = 0; i < nr_conn; ++i)
                    if (peers_stopped[i])
                        peer_stopped = true;
                if (peer_stopped)
                    break;
                readable.wait();
                readable.reset();
            }
        }
        try { socket.shutdownSend(); } catch (...) {}
        self_stopped = true;
        for (int i = 0; i < nr_conn; ++i)
            writables[i]->set();
    }
};

int main(int argc, char **argv)
{
    config.load("multisocks.txt");
    for (int i = 1; i < argc; ++i)
        if (config.load(argv[i]))
            return 1;
    if (!config.s("log").empty())
        freopen(config.s("log").c_str(), "w", stdout);
    ErrorHandler::set(new error_handler);
    fflush(stdout);
    try
    {
        int nr_conn = config.i("nr_conn");
        bool divider_stopped = false, combiner_stopped = false;
        bool *readers_stopped = new bool[nr_conn](), *writers_stopped = new bool[nr_conn]();
        Event in_readable(false), out_writable(false);
        in_readable.reset();
        out_writable.set();
        vector<Event *> in_writables, out_readables;
        for (int i = 0; i < nr_conn; ++i)
        {
            in_writables.push_back(new Event);
            in_writables.back()->set();
            out_readables.push_back(new Event);
            out_readables.back()->reset();
        }
        vector<StreamSocket> remotes;
        if (config.s("remote") == "listen")
        {
            ServerSocket server;
            if (config.s("remote.protocol") == "ipv6")
                server.bind6(config.i("remote.port"), true, true);
            else
                server.bind(config.i("remote.port"), true);
            server.listen();
            for (int i = 0; i < nr_conn; ++i)
            {
                SocketAddress client_addr;
                remotes.push_back(server.acceptConnection(client_addr));
                remotes.back().setNoDelay(true);
                printf("[.] Remote incoming: %s\n", client_addr.toString().c_str());
                fflush(stdout);
                if (client_addr.host() != remotes.front().peerAddress().host())
                    throw Exception(string("client addresses mismatch"));
            }
            server.close();
        }
        else
        {
            SocketAddress server_addr(config.s("remote.host"), config.i("remote.port"));
            for (int i = 0; i < nr_conn; ++i)
            {
                StreamSocket remote;
                if (!config.s("remote.bind").empty())
                    remote.impl()->bind(SocketAddress(config.s("remote.bind"), 0), true);
                remote.connect(server_addr);
                remote.setNoDelay(true);
                remotes.push_back(remote);
                printf("[.] Connected to remote from: %s\n", remote.address().toString().c_str());
                fflush(stdout);
            }
        }
        vector<FIFOBuffer *> in_buffers, out_buffers;
        vector<reader *> readers;
        vector<writer *> writers;
        Thread *reader_threads = new Thread[nr_conn], *writer_threads = new Thread[nr_conn];
        for (int i = 0; i < nr_conn; ++i)
        {
            in_buffers.push_back(new FIFOBuffer(config.i("buffer_size")));
            out_buffers.push_back(new FIFOBuffer(config.i("buffer_size")));
            readers.push_back(new reader(i, remotes[i], *out_readables[i], out_writable, *out_buffers.back(), readers_stopped[i], divider_stopped));
            writers.push_back(new writer(i, remotes[i], in_readable, *in_writables[i], *in_buffers.back(), writers_stopped[i], combiner_stopped));
            reader_threads[i].setStackSize(65536);
            writer_threads[i].setStackSize(65536);
            reader_threads[i].start(*readers.back());
            writer_threads[i].start(*writers.back());
        }
        StreamSocket local;
        if (config.s("local") == "listen")
        {
            ServerSocket server;
            if (config.s("local.protocol") == "ipv6")
                server.bind6(config.i("local.port"), true, true);
            else
                server.bind(config.i("local.port"), true);
            server.listen();
            local = server.acceptConnection();
            printf("[.] Local incoming: %s\n", local.peerAddress().toString().c_str());
            fflush(stdout);
            local.setNoDelay(true);
            server.close();
        }
        else
        {
            SocketAddress server_addr(config.s("local.host"), config.i("local.port"));
            local.connect(server_addr);
            local.setNoDelay(true);
            printf("[.] Connected to local from: %s\n", local.address().toString().c_str());
            fflush(stdout);
        }
        divider *pdivider = new divider(nr_conn, local, out_readables, out_writable, out_buffers, divider_stopped, readers_stopped);
        combiner *pcombiner = new combiner(nr_conn, local, in_readable, in_writables, in_buffers, combiner_stopped, writers_stopped);
        Thread divider_thread, combiner_thread;
        divider_thread.setStackSize(65536);
        combiner_thread.setStackSize(65536);
        divider_thread.start(*pdivider);
        combiner_thread.start(*pcombiner);
        printf("[.] Connection established\n");
        fflush(stdout);
        divider_thread.join();
        combiner_thread.join();
        local.close();
        for (int i = 0; i < nr_conn; ++i)
        {
            reader_threads[i].join();
            writer_threads[i].join();
            remotes[i].close();
        }
        printf("[.] Connection closed\n");
    }
    catch (Exception &exc)
    {
        ErrorHandler::handle(exc);
    }
    catch (exception &exc)
    {
        ErrorHandler::handle(exc);
    }
    catch (...)
    {
        ErrorHandler::handle();
    }
    return 0;
}
