#ifndef MOD_NATIVE_REAGENTS_PROTOCOL_H
#define MOD_NATIVE_REAGENTS_PROTOCOL_H

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace NativeReagents::Protocol
{
constexpr std::uint32_t Version = 2;
constexpr std::size_t MaxPayload = 240;

struct Request
{
    std::uint32_t version = 0;
    std::uint32_t id = 0;
    std::string command;
    std::vector<std::string> arguments;
};

std::optional<Request> Parse(std::string_view payload);
bool ParseUInt32(std::string_view value, std::uint32_t& output);
std::string Reply(std::uint32_t requestId, std::string_view kind, std::string_view body = {});
}

#endif
