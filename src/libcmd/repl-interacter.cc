#include <cstdio>

extern "C" char* readline(const char* prompt);

#include "signals.hh"
#include "finally.hh"
#include "repl-interacter.hh"
#include "file-system.hh"
#include "repl.hh"
#include "environment-variables.hh"

namespace nix {

namespace {
// Used to communicate to NixRepl::getLine whether a signal occurred in ::readline.
volatile sig_atomic_t g_signal_received = 0;

void sigintHandler(int signo)
{
    g_signal_received = signo;
}
};

static detail::ReplCompleterMixin * curRepl; // ugly

ReadlineLikeInteracter::Guard ReadlineLikeInteracter::init(detail::ReplCompleterMixin * repl)
{
    // Allow nix-repl specific settings in .inputrc
    try {
        createDirs(dirOf(historyFile));
    } catch (SystemError & e) {
        logWarning(e.info());
    }
    auto oldRepl = curRepl;
    curRepl = repl;
    Guard restoreRepl([oldRepl] { curRepl = oldRepl; });
    return restoreRepl;
}

static constexpr const char * promptForType(ReplPromptType promptType)
{
    switch (promptType) {
    case ReplPromptType::ReplPrompt:
        return "nix-repl> ";
    case ReplPromptType::ContinuationPrompt:
        return "          ";
    }
    assert(false);
}

bool ReadlineLikeInteracter::getLine(std::string & input, ReplPromptType promptType)
{
#ifndef _WIN32 // TODO use more signals.hh for this
    struct sigaction act, old;
    sigset_t savedSignalMask, set;

    auto setupSignals = [&]() {
        act.sa_handler = sigintHandler;
        sigfillset(&act.sa_mask);
        act.sa_flags = 0;
        if (sigaction(SIGINT, &act, &old))
            throw SysError("installing handler for SIGINT");

        sigemptyset(&set);
        sigaddset(&set, SIGINT);
        if (sigprocmask(SIG_UNBLOCK, &set, &savedSignalMask))
            throw SysError("unblocking SIGINT");
    };
    auto restoreSignals = [&]() {
        if (sigprocmask(SIG_SETMASK, &savedSignalMask, nullptr))
            throw SysError("restoring signals");

        if (sigaction(SIGINT, &old, 0))
            throw SysError("restoring handler for SIGINT");
    };

    setupSignals();
#endif
    char * s = readline(promptForType(promptType));
    Finally doFree([&]() { free(s); });
#ifndef _WIN32 // TODO use more signals.hh for this
    restoreSignals();
#endif

    if (g_signal_received) {
        g_signal_received = 0;
        input.clear();
        return true;
    }

    // editline doesn't echo the input to the output when non-interactive, unlike readline
    // this results in a different behavior when running tests. The echoing is
    // quite useful for reading the test output, so we add it here.
    if (auto e = getEnv("_NIX_TEST_REPL_ECHO"); s && e && *e == "1")
    {
        // This is probably not right for multi-line input, but we don't use that
        // in the characterisation tests, so it's fine.
        std::cout << promptForType(promptType) << s << std::endl;
    }

    if (!s)
        return false;
    input += s;
    input += '\n';

    return true;
}

};
