pub usingnamespace @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});

pub usingnamespace @cImport({
    @cInclude("stb_image.h");
});
