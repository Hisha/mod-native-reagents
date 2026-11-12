#include "../src/NativeReagentsProtocol.h"
#include <cassert>
#include <iostream>

int main()
{
    using namespace NativeReagents::Protocol;
    auto hello = Parse("2|17|HELLO");
    assert(hello && hello->version == 2 && hello->id == 17 && hello->command == "HELLO");
    auto withdrawal = Parse("2|18|WITHDRAW|36901|20");
    assert(withdrawal && withdrawal->arguments.size() == 2 && withdrawal->arguments[0] == "36901");
    assert(!Parse("1|17|HELLO"));
    assert(!Parse("2|0|HELLO"));
    assert(!Parse("2|x|HELLO"));
    assert(!Parse(std::string(241, 'x')));
    std::uint32_t value = 0;
    assert(ParseUInt32("4294967295", value) && value == 4294967295u);
    assert(!ParseUInt32("4294967296", value));
    assert(Reply(9, "OK", "done") == "2|9|OK|done");
    assert(Reply(9, "DATA", std::string(240, 'x')).find("response-too-large") != std::string::npos);
    std::cout << "PASS protocol parsing, bounds, versioning, framing\n";
}
