#include "NativeReagentsProtocol.h"

#include <charconv>

namespace NativeReagents::Protocol
{
bool ParseUInt32(std::string_view value, std::uint32_t& output)
{
    if (value.empty() || value.size() > 10)
        return false;
    auto result = std::from_chars(value.data(), value.data() + value.size(), output);
    return result.ec == std::errc{} && result.ptr == value.data() + value.size();
}

std::optional<Request> Parse(std::string_view payload)
{
    if (payload.empty() || payload.size() > MaxPayload)
        return std::nullopt;

    std::vector<std::string> fields;
    std::size_t start = 0;
    while (start <= payload.size())
    {
        std::size_t end = payload.find('|', start);
        fields.emplace_back(payload.substr(start, end == std::string_view::npos ? payload.size() - start : end - start));
        if (end == std::string_view::npos)
            break;
        start = end + 1;
    }
    if (fields.size() < 3)
        return std::nullopt;

    Request request;
    if (!ParseUInt32(fields[0], request.version) || request.version != Version ||
        !ParseUInt32(fields[1], request.id) || !request.id || fields[2].empty() || fields[2].size() > 16)
        return std::nullopt;
    request.command = fields[2];
    request.arguments.assign(fields.begin() + 3, fields.end());
    return request;
}

std::string Reply(std::uint32_t requestId, std::string_view kind, std::string_view body)
{
    std::string result = std::to_string(Version) + "|" + std::to_string(requestId) + "|" + std::string(kind);
    if (!body.empty())
        result += "|" + std::string(body);
    return result.size() <= MaxPayload ? result : std::to_string(Version) + "|" + std::to_string(requestId) + "|ERR|response-too-large";
}
}
