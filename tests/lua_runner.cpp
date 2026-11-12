extern "C"
{
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

#include <iostream>
#include <string>

#ifndef LUA_OK
#define LUA_OK 0
#endif

int main(int argc, char** argv)
{
    if (argc < 2)
        return 2;
    lua_State* state = luaL_newstate();
    luaL_openlibs(state);
    if (argc > 2 && std::string(argv[1]) == "--syntax")
    {
        for (int index = 2; index < argc; ++index)
        {
            if (luaL_loadfile(state, argv[index]) != LUA_OK)
            {
                std::cerr << lua_tostring(state, -1) << '\n';
                lua_close(state);
                return 1;
            }
            lua_pop(state, 1);
        }
        lua_close(state);
        std::cout << "PASS Lua syntax\n";
        return 0;
    }
    int result = luaL_dofile(state, argv[1]);
    if (result != LUA_OK)
    {
        std::cerr << lua_tostring(state, -1) << '\n';
        lua_close(state);
        return 1;
    }
    lua_close(state);
    return 0;
}
