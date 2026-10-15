#pragma once
#include <optional>
#include <string>

inline std::optional<std::string> ArgumentFromCommandLineUntilNextSpace(char* commandLine, const char* needle, const size_t needleLen)
{
    const auto line = std::string(commandLine);
    const auto argumentStart = line.find(needle);
    if (argumentStart == -1)
    {
        return {};
    }

    // We need a manual passing of needleLen as we can't easily constexpr strlen inside here.
    const auto argumentValueStart = argumentStart + needleLen;
    const auto argumentValueEnd = line.find(' ', argumentValueStart);

    return line.substr(argumentValueStart, argumentValueEnd - argumentValueStart);
}

inline std::optional<std::string> ParseHostFromCommandLine(char* commandLine) {
    constexpr auto needle = "--cyberverse-server-address=";
    constexpr auto needleLen = std::char_traits<char>::length(needle);
    return ArgumentFromCommandLineUntilNextSpace(commandLine, needle, needleLen);
}

inline std::optional<uint16_t> ParsePortFromCommandLine(char* commandLine) {
    constexpr auto needle = "--cyberverse-server-port=";
    constexpr auto needleLen = std::char_traits<char>::length(needle);
    const auto portString = ArgumentFromCommandLineUntilNextSpace(commandLine, needle, needleLen);
    if (!portString.has_value())
    {
        return {};
    }

    return std::stoi(portString.value());
}

// Player name from the Vault Hunters launcher; without it the Windows user name is used.
inline std::optional<std::string> ParseNameFromCommandLine(char* commandLine) {
    constexpr auto needle = "--cyberverse-name=";
    constexpr auto needleLen = std::char_traits<char>::length(needle);
    auto name = ArgumentFromCommandLineUntilNextSpace(commandLine, needle, needleLen);
    if (!name.has_value() || name->empty())
    {
        return {};
    }
    if (name->size() > 32)
    {
        name->resize(32);
    }
    return name;
}
